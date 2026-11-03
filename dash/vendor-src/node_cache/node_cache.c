// SPDX-License-Identifier: GPL-2.0-only
/*
 * Xiaomi F2FS node-page compressed cache.
 *
 * The vendor implementation is a small LZ4/zsmalloc cache attached to the
 * node mapping of /data. This version keeps the observable policy while using
 * native 6.12 APIs and explicit lifetime ownership for built-in use.
 */
#define pr_fmt(fmt) "f2fs-node-cache: " fmt

#include <linux/atomic.h>
#include <linux/fs.h>
#include <linux/f2fs_fs.h>
#include <linux/gfp.h>
#include <linux/init.h>
#include <linux/kstrtox.h>
#include <linux/limits.h>
#include <linux/list.h>
#include <linux/lz4.h>
#include <linux/namei.h>
#include <linux/mount.h>
#include <linux/percpu.h>
#include <linux/preempt.h>
#include <linux/radix-tree.h>
#include <linux/refcount.h>
#include <linux/shrinker.h>
#include <linux/slab.h>
#include <linux/spinlock.h>
#include <linux/string.h>
#include <linux/sysfs.h>
#include <linux/wait.h>
#include <linux/workqueue.h>
#include <linux/zsmalloc.h>

#include <trace/hooks/blk.h>
#include <trace/hooks/fs.h>
#include <trace/hooks/mm.h>
#include <trace/hooks/vmscan.h>

#include "f2fs.h"

#define NODE_CACHE_DEFAULT_MAX_BYTES	(40U * 1024U * 1024U)
#define NODE_CACHE_DEFAULT_SHRINK_WMARK	75U
#define NODE_CACHE_DEFAULT_COMP_RATIO	50U
#define NODE_CACHE_GFP	(__GFP_KSWAPD_RECLAIM | __GFP_NOWARN)

struct node_cache_entry {
	struct list_head list;
	unsigned long handle;
	u32 compressed_size;
	nid_t nid;
};

struct node_cache_instance {
	struct super_block *sb;
	struct radix_tree_root entries;
	struct list_head entry_list;
	struct list_head manager_list;
	raw_spinlock_t lock;
	refcount_t refs;
	u32 entry_count;
	u32 compressed_bytes;
	u32 max_bytes;
	u32 shrink_wmark;
	u32 comp_ratio;
	u32 swapin_count;
	u32 invalid_count;
	u32 shrink_count;
};

struct node_cache_cpu {
	char *compressed;
	void *workspace;
};

struct node_cache_manager {
	raw_spinlock_t lock;
	struct node_cache_instance *active;
	struct list_head retired;
	struct work_struct free_work;
	wait_queue_head_t live_waitq;
	atomic_t live_instances;
};

static struct node_cache_manager node_cache_mgr;
static struct zs_pool *node_cache_pool;
static struct kmem_cache *node_cache_slab;
static struct node_cache_cpu __percpu *node_cache_buf;
static struct shrinker *node_cache_shrinker;
/* The vendor object ships with compression enabled; tracing is opt-in. */
static bool comp_enable = true;
static bool trace_enable;
static unsigned int node_cache_max_bytes = NODE_CACHE_DEFAULT_MAX_BYTES;
static unsigned int node_cache_shrink_wmark = NODE_CACHE_DEFAULT_SHRINK_WMARK;
static unsigned int node_cache_comp_ratio = NODE_CACHE_DEFAULT_COMP_RATIO;

static struct node_cache_instance *node_cache_get_active(struct super_block *sb)
{
	struct node_cache_instance *inst;
	unsigned long flags;

	raw_spin_lock_irqsave(&node_cache_mgr.lock, flags);
	inst = node_cache_mgr.active;
	if (!inst || (sb && inst->sb != sb) ||
	    !refcount_inc_not_zero(&inst->refs))
		inst = NULL;
	raw_spin_unlock_irqrestore(&node_cache_mgr.lock, flags);
	return inst;
}

static void node_cache_free_entry(struct node_cache_entry *entry)
{
	if (!entry)
		return;
	if (entry->handle)
		zs_free(node_cache_pool, entry->handle);
	kmem_cache_free(node_cache_slab, entry);
}

static void node_cache_free_instance(struct node_cache_instance *inst)
{
	LIST_HEAD(entries);
	struct node_cache_entry *entry, *tmp;
	unsigned long flags;

	raw_spin_lock_irqsave(&inst->lock, flags);
	while (!list_empty(&inst->entry_list)) {
		entry = list_first_entry(&inst->entry_list,
					struct node_cache_entry, list);
		radix_tree_delete(&inst->entries, entry->nid);
		list_move_tail(&entry->list, &entries);
		if (inst->entry_count)
			inst->entry_count--;
		if (inst->compressed_bytes >= entry->compressed_size)
			inst->compressed_bytes -= entry->compressed_size;
		else
			inst->compressed_bytes = 0;
	}
	raw_spin_unlock_irqrestore(&inst->lock, flags);

	list_for_each_entry_safe(entry, tmp, &entries, list) {
		list_del_init(&entry->list);
		node_cache_free_entry(entry);
	}
	kfree(inst);
	if (atomic_dec_and_test(&node_cache_mgr.live_instances))
		wake_up_all(&node_cache_mgr.live_waitq);
}

static void node_cache_free_workfn(struct work_struct *work)
{
	LIST_HEAD(retired);
	struct node_cache_instance *inst, *tmp;
	unsigned long flags;

	raw_spin_lock_irqsave(&node_cache_mgr.lock, flags);
	list_splice_init(&node_cache_mgr.retired, &retired);
	raw_spin_unlock_irqrestore(&node_cache_mgr.lock, flags);

	list_for_each_entry_safe(inst, tmp, &retired, manager_list) {
		list_del_init(&inst->manager_list);
		node_cache_free_instance(inst);
	}
}

static void node_cache_put(struct node_cache_instance *inst)
{
	unsigned long flags;

	if (!inst || !refcount_dec_and_test(&inst->refs))
		return;
	raw_spin_lock_irqsave(&node_cache_mgr.lock, flags);
	list_add_tail(&inst->manager_list, &node_cache_mgr.retired);
	raw_spin_unlock_irqrestore(&node_cache_mgr.lock, flags);
	queue_work(system_wq, &node_cache_mgr.free_work);
}

static bool node_cache_is_node_mapping(struct address_space *mapping,
					       struct super_block **sbp)
{
	struct inode *inode;
	struct f2fs_sb_info *sbi;
	struct super_block *sb;

	if (!mapping || !mapping->host)
		return false;
	inode = mapping->host;
	sb = inode->i_sb;
	if (!sb || sb->s_magic != F2FS_SUPER_MAGIC || !sb->s_fs_info)
		return false;
	sbi = F2FS_SB(sb);
	if (!sbi->node_inode || inode != sbi->node_inode ||
	    mapping != NODE_MAPPING(sbi))
		return false;
	if (sbp)
		*sbp = sb;
	return true;
}

static struct node_cache_entry *
node_cache_lookup_locked(struct node_cache_instance *inst,
					 struct super_block *owner, nid_t nid,
					 bool invalid)
{
	struct node_cache_entry *entry;
	unsigned long flags;

	raw_spin_lock_irqsave(&inst->lock, flags);
	/* Do not consume an entry after the owning superblock has detached. */
	if (owner && inst->sb != owner) {
		raw_spin_unlock_irqrestore(&inst->lock, flags);
		return NULL;
	}
	entry = radix_tree_delete(&inst->entries, nid);
	if (entry) {
		list_del_init(&entry->list);
		if (inst->entry_count)
			inst->entry_count--;
		if (inst->compressed_bytes >= entry->compressed_size)
			inst->compressed_bytes -= entry->compressed_size;
		else
			inst->compressed_bytes = 0;
		if (invalid)
			inst->invalid_count++;
		else
			inst->swapin_count++;
	}
	raw_spin_unlock_irqrestore(&inst->lock, flags);
	return entry;
}

static unsigned int node_cache_shrink_instance(struct node_cache_instance *inst,
						unsigned int nr_to_scan,
						struct super_block *owner)
{
	LIST_HEAD(entries);
	struct node_cache_entry *entry, *tmp;
	unsigned int freed = 0;
	unsigned long flags;

	if (!raw_spin_trylock_irqsave(&inst->lock, flags))
		return 0;
	if (!inst->sb || (owner && inst->sb != owner))
		goto out_unlock;
	while (!list_empty(&inst->entry_list)) {
		entry = list_first_entry(&inst->entry_list,
					struct node_cache_entry, list);
		radix_tree_delete(&inst->entries, entry->nid);
		list_move_tail(&entry->list, &entries);
		if (inst->entry_count)
			inst->entry_count--;
		if (inst->compressed_bytes >= entry->compressed_size)
			inst->compressed_bytes -= entry->compressed_size;
		else
			inst->compressed_bytes = 0;
		inst->shrink_count++;
		freed++;
		if (freed >= nr_to_scan &&
		    inst->compressed_bytes < inst->max_bytes)
			break;
	}
out_unlock:
	raw_spin_unlock_irqrestore(&inst->lock, flags);

	list_for_each_entry_safe(entry, tmp, &entries, list) {
		list_del_init(&entry->list);
		node_cache_free_entry(entry);
	}
	if (freed && trace_enable)
		pr_info_ratelimited("shrink freed=%u\n", freed);
	return freed;
}

static unsigned long node_cache_shrink_count(struct shrinker *shrinker,
						struct shrink_control *sc)
{
	struct node_cache_instance *inst;
	unsigned long flags;
	u32 bytes, count, target;

	inst = node_cache_get_active(NULL);
	if (!inst)
		return SHRINK_EMPTY;
	raw_spin_lock_irqsave(&inst->lock, flags);
	bytes = inst->compressed_bytes;
	count = inst->entry_count;
	target = inst->max_bytes * inst->shrink_wmark / 100U;
	raw_spin_unlock_irqrestore(&inst->lock, flags);
	node_cache_put(inst);
	if (!bytes || bytes <= target || !count)
		return SHRINK_EMPTY;
	return max_t(unsigned long, 1,
			(unsigned long)(bytes - target) * count / bytes);
}

static unsigned long node_cache_shrink_scan(struct shrinker *shrinker,
						struct shrink_control *sc)
{
	struct node_cache_instance *inst;
	unsigned int ret;

	inst = node_cache_get_active(NULL);
	if (!inst)
		return SHRINK_EMPTY;
	ret = node_cache_shrink_instance(inst, sc->nr_to_scan, NULL);
	node_cache_put(inst);
	return ret;
}

static bool node_cache_folio_eligible(struct address_space *mapping,
					      struct folio *folio,
					      struct super_block **sbp)
{
	if (!node_cache_is_node_mapping(mapping, sbp) || !folio)
		return false;
	/* Match the vendor raw page-flag guard: skip swapcache folios. */
	if (folio_nr_pages(folio) != 1 || folio_test_large(folio) ||
	    folio_test_swapcache(folio))
		return false;
	return true;
}

static void vh_remove_mapping(void *data, struct address_space *mapping,
				      struct folio *folio, bool reclaimed)
{
	struct node_cache_instance *inst;
	struct node_cache_entry *entry;
	struct node_cache_cpu *cpu_buf;
	struct super_block *sb;
	unsigned long handle;
	void *src;
	int compressed_size;
	unsigned long flags;
	u32 current_bytes, max_bytes;

	if (!reclaimed || !READ_ONCE(comp_enable) ||
	    !node_cache_folio_eligible(mapping, folio, &sb))
		return;
	inst = node_cache_get_active(sb);
	if (!inst)
		return;

	/* Do not recurse into direct reclaim from the reclaim hook. */
	raw_spin_lock_irqsave(&inst->lock, flags);
	current_bytes = inst->compressed_bytes;
	max_bytes = inst->max_bytes;
	raw_spin_unlock_irqrestore(&inst->lock, flags);
	if (current_bytes > max_bytes)
		node_cache_shrink_instance(inst, 16, sb);
	preempt_disable();
	cpu_buf = this_cpu_ptr(node_cache_buf);
	src = kmap_local_folio(folio, 0);
	compressed_size = LZ4_compress_default(src, cpu_buf->compressed,
						PAGE_SIZE, PAGE_SIZE,
						cpu_buf->workspace);
	kunmap_local(src);
	if (compressed_size <= 0) {
		preempt_enable();
		goto out_put;
	}
	raw_spin_lock_irqsave(&inst->lock, flags);
	if (inst->comp_ratio == 0 ||
	    compressed_size >= PAGE_SIZE * inst->comp_ratio / 100U) {
		raw_spin_unlock_irqrestore(&inst->lock, flags);
		preempt_enable();
		goto out_put;
	}
	raw_spin_unlock_irqrestore(&inst->lock, flags);

	handle = zs_malloc(node_cache_pool, compressed_size, NODE_CACHE_GFP);
	if (!handle || IS_ERR_VALUE(handle)) {
		preempt_enable();
		goto out_put;
	}
	{
		void *dst = zs_map_object(node_cache_pool, handle, ZS_MM_WO);

		memcpy(dst, cpu_buf->compressed, compressed_size);
		zs_unmap_object(node_cache_pool, handle);
	}

	entry = kmem_cache_alloc(node_cache_slab, NODE_CACHE_GFP);
	if (!entry) {
		zs_free(node_cache_pool, handle);
		preempt_enable();
		goto out_put;
	}
	INIT_LIST_HEAD(&entry->list);
	entry->handle = handle;
	entry->compressed_size = compressed_size;
	entry->nid = (nid_t)folio->index;

	raw_spin_lock_irqsave(&inst->lock, flags);
	if (inst->sb != sb ||
	    radix_tree_insert(&inst->entries, entry->nid, entry)) {
		raw_spin_unlock_irqrestore(&inst->lock, flags);
		node_cache_free_entry(entry);
		preempt_enable();
		goto out_put;
	}
	list_add_tail(&entry->list, &inst->entry_list);
	inst->entry_count++;
	inst->compressed_bytes += compressed_size;
	raw_spin_unlock_irqrestore(&inst->lock, flags);
	preempt_enable();
	if (trace_enable)
		pr_info_ratelimited("compress idx=%lu len=%d\n",
				    folio->index, compressed_size);
out_put:
	node_cache_put(inst);
}

static void vh_remove_mapping_failed(void *data,
					     struct address_space *mapping,
					     struct folio *folio, bool reclaimed)
{
	struct node_cache_instance *inst;
	struct node_cache_entry *entry;
	struct super_block *sb;

	if (!reclaimed || !node_cache_folio_eligible(mapping, folio, &sb))
		return;
	inst = node_cache_get_active(sb);
	if (!inst)
		return;
	entry = node_cache_lookup_locked(inst, sb, (nid_t)folio->index, true);
	node_cache_put(inst);
	if (entry) {
		node_cache_free_entry(entry);
		if (trace_enable)
			pr_info_ratelimited("invalid idx=%lu\n", folio->index);
	}
}

static void vh_filemap_get_folio_end(void *data,
					      struct address_space *mapping,
					      struct folio *folio)
{
	struct node_cache_instance *inst;
	struct node_cache_entry *entry;
	struct super_block *sb;
	void *src, *dst;
	int ret;

	if (!folio || folio_test_uptodate(folio) ||
	    !node_cache_is_node_mapping(mapping, &sb) ||
	    folio_nr_pages(folio) != 1)
		return;
	inst = node_cache_get_active(sb);
	if (!inst)
		return;
	entry = node_cache_lookup_locked(inst, sb, (nid_t)folio->index, false);
	node_cache_put(inst);
	if (!entry)
		return;

	src = zs_map_object(node_cache_pool, entry->handle, ZS_MM_RO);
	dst = kmap_local_folio(folio, 0);
	ret = LZ4_decompress_safe(src, dst, entry->compressed_size, PAGE_SIZE);
	kunmap_local(dst);
	zs_unmap_object(node_cache_pool, entry->handle);
	if (ret == PAGE_SIZE) {
		folio_mark_uptodate(folio);
		if (trace_enable)
			pr_info_ratelimited("decompress idx=%lu\n", folio->index);
	} else {
		pr_err_ratelimited("decompress_fail idx=%lu len=%d\n",
				   folio->index, ret);
	}
	node_cache_free_entry(entry);
}

static int node_cache_attach_sb(struct super_block *sb)
{
	struct node_cache_instance *inst;
	int ret = -ENOMEM;

	if (!sb || sb->s_magic != F2FS_SUPER_MAGIC || !sb->s_fs_info ||
		!F2FS_SB(sb)->node_inode)
		return -EINVAL;
	inst = kzalloc(sizeof(*inst), NODE_CACHE_GFP);
	if (!inst)
		return -ENOMEM;
	inst->sb = sb;
	INIT_RADIX_TREE(&inst->entries, NODE_CACHE_GFP);
	INIT_LIST_HEAD(&inst->entry_list);
	INIT_LIST_HEAD(&inst->manager_list);
	raw_spin_lock_init(&inst->lock);
	refcount_set(&inst->refs, 1);
	inst->max_bytes = READ_ONCE(node_cache_max_bytes);
	inst->shrink_wmark = READ_ONCE(node_cache_shrink_wmark);
	inst->comp_ratio = READ_ONCE(node_cache_comp_ratio);
	raw_spin_lock(&node_cache_mgr.lock);
	if (!node_cache_mgr.active) {
		node_cache_mgr.active = inst;
		atomic_inc(&node_cache_mgr.live_instances);
		ret = 0;
	}
	raw_spin_unlock(&node_cache_mgr.lock);
	if (ret)
		kfree(inst);
	else
		pr_info("attached to /data\n");
	return ret;
}

static void vh_do_new_mount_fc(void *data, struct path *mountpoint,
				       struct vfsmount *mnt)
{
	char *buf;
	char *name;

	if (!mountpoint || !mnt || !mnt->mnt_sb ||
	    mnt->mnt_sb->s_magic != F2FS_SUPER_MAGIC)
		return;
	buf = kmalloc(PATH_MAX, NODE_CACHE_GFP);
	if (!buf)
		return;
	name = d_path(mountpoint, buf, PATH_MAX);
	if (!IS_ERR(name) && !strcmp(name, "/data"))
		node_cache_attach_sb(mnt->mnt_sb);
	kfree(buf);
}

static void vh_put_super(void *data, struct super_block *sb)
{
	struct node_cache_instance *inst;
	unsigned long flags;

	if (!sb)
		return;
	raw_spin_lock_irqsave(&node_cache_mgr.lock, flags);
	inst = node_cache_mgr.active;
	if (inst && inst->sb == sb) {
		node_cache_mgr.active = NULL;
		raw_spin_lock(&inst->lock);
		inst->sb = NULL;
		raw_spin_unlock(&inst->lock);
	} else {
		inst = NULL;
	}
	raw_spin_unlock_irqrestore(&node_cache_mgr.lock, flags);
	if (inst)
		node_cache_put(inst);
}

static void node_cache_attach_existing(void)
{
	struct path path;
	struct super_block *sb;

	if (kern_path("/data", LOOKUP_FOLLOW, &path))
		return;
	sb = path.dentry ? path.dentry->d_sb : NULL;
	if (sb && sb->s_magic == F2FS_SUPER_MAGIC)
		node_cache_attach_sb(sb);
	path_put(&path);
}

static ssize_t stat_show(struct kobject *kobj, struct kobj_attribute *attr,
				 char *buf)
{
	struct node_cache_instance *inst;
	unsigned long flags;
	u32 count = 0, bytes = 0, swapin = 0, invalid = 0, shrink = 0;
	bool init = false;

	inst = node_cache_get_active(NULL);
	if (inst) {
		raw_spin_lock_irqsave(&inst->lock, flags);
		count = inst->entry_count;
		bytes = inst->compressed_bytes;
		swapin = inst->swapin_count;
		invalid = inst->invalid_count;
		shrink = inst->shrink_count;
		init = true;
		raw_spin_unlock_irqrestore(&inst->lock, flags);
		node_cache_put(inst);
	}
	return sysfs_emit(buf,
			"init                     %d\n"
			"live_instances           %d\n"
			"comp_enable              %d\n"
			"trace_enable             %d\n"
			"cur_cnt                  %u\n"
			"cur_bytes                %u\n"
			"swapin_cnt               %u\n"
			"invalid_cnt              %u\n"
			"shrink_cnt               %u\n",
			init, atomic_read(&node_cache_mgr.live_instances),
			READ_ONCE(comp_enable), READ_ONCE(trace_enable), count, bytes,
			swapin, invalid, shrink);
}

static ssize_t max_bytes_show(struct kobject *kobj,
				      struct kobj_attribute *attr, char *buf)
{
	return sysfs_emit(buf, "%u\n", READ_ONCE(node_cache_max_bytes));
}

static ssize_t max_bytes_store(struct kobject *kobj,
				       struct kobj_attribute *attr,
				       const char *buf, size_t count)
{
	unsigned int value;
	struct node_cache_instance *inst;
	unsigned long flags;

	if (kstrtouint(buf, 0, &value))
		return -EINVAL;
	WRITE_ONCE(node_cache_max_bytes, value);
	inst = node_cache_get_active(NULL);
	if (inst) {
		raw_spin_lock_irqsave(&inst->lock, flags);
		inst->max_bytes = value;
		raw_spin_unlock_irqrestore(&inst->lock, flags);
		node_cache_put(inst);
	}
	return count;
}

static ssize_t shrink_wmark_show(struct kobject *kobj,
					struct kobj_attribute *attr, char *buf)
{
	return sysfs_emit(buf, "%u\n", READ_ONCE(node_cache_shrink_wmark));
}

static ssize_t shrink_wmark_store(struct kobject *kobj,
					 struct kobj_attribute *attr,
					 const char *buf, size_t count)
{
	unsigned int value;
	struct node_cache_instance *inst;
	unsigned long flags;

	if (kstrtouint(buf, 0, &value) || value > 100)
		return -EINVAL;
	WRITE_ONCE(node_cache_shrink_wmark, value);
	inst = node_cache_get_active(NULL);
	if (inst) {
		raw_spin_lock_irqsave(&inst->lock, flags);
		inst->shrink_wmark = value;
		raw_spin_unlock_irqrestore(&inst->lock, flags);
		node_cache_put(inst);
	}
	return count;
}

static ssize_t comp_ratio_show(struct kobject *kobj,
				       struct kobj_attribute *attr, char *buf)
{
	return sysfs_emit(buf, "%u\n", READ_ONCE(node_cache_comp_ratio));
}

static ssize_t comp_ratio_store(struct kobject *kobj,
					struct kobj_attribute *attr,
					const char *buf, size_t count)
{
	unsigned int value;
	struct node_cache_instance *inst;
	unsigned long flags;

	if (kstrtouint(buf, 0, &value) || value > 100)
		return -EINVAL;
	WRITE_ONCE(node_cache_comp_ratio, value);
	inst = node_cache_get_active(NULL);
	if (inst) {
		raw_spin_lock_irqsave(&inst->lock, flags);
		inst->comp_ratio = value;
		raw_spin_unlock_irqrestore(&inst->lock, flags);
		node_cache_put(inst);
	}
	return count;
}

static ssize_t comp_enable_show(struct kobject *kobj,
					struct kobj_attribute *attr, char *buf)
{
	return sysfs_emit(buf, "%d\n", READ_ONCE(comp_enable));
}

static ssize_t comp_enable_store(struct kobject *kobj,
					 struct kobj_attribute *attr,
					 const char *buf, size_t count)
{
	bool value;

	if (kstrtobool(buf, &value))
		return -EINVAL;
	WRITE_ONCE(comp_enable, value);
	return count;
}

static ssize_t trace_enable_show(struct kobject *kobj,
					struct kobj_attribute *attr, char *buf)
{
	return sysfs_emit(buf, "%d\n", READ_ONCE(trace_enable));
}

static ssize_t trace_enable_store(struct kobject *kobj,
					 struct kobj_attribute *attr,
					 const char *buf, size_t count)
{
	bool value;

	if (kstrtobool(buf, &value))
		return -EINVAL;
	WRITE_ONCE(trace_enable, value);
	return count;
}

static struct kobj_attribute stat_attr = __ATTR_RO(stat);
static struct kobj_attribute max_bytes_attr = __ATTR_RW(max_bytes);
static struct kobj_attribute shrink_wmark_attr = __ATTR_RW(shrink_wmark);
static struct kobj_attribute comp_ratio_attr = __ATTR_RW(comp_ratio);
static struct kobj_attribute comp_enable_attr = __ATTR_RW(comp_enable);
static struct kobj_attribute trace_enable_attr = __ATTR_RW(trace_enable);

static struct attribute *node_cache_attrs[] = {
	&stat_attr.attr,
	&max_bytes_attr.attr,
	&shrink_wmark_attr.attr,
	&comp_ratio_attr.attr,
	&comp_enable_attr.attr,
	&trace_enable_attr.attr,
	NULL,
};

static const struct attribute_group node_cache_attr_group = {
	.name = "node_cache",
	.attrs = node_cache_attrs,
};

static int __init node_cache_init(void)
{
	int cpu;
	int ret = -ENOMEM;

	raw_spin_lock_init(&node_cache_mgr.lock);
	INIT_LIST_HEAD(&node_cache_mgr.retired);
	INIT_WORK(&node_cache_mgr.free_work, node_cache_free_workfn);
	init_waitqueue_head(&node_cache_mgr.live_waitq);
	atomic_set(&node_cache_mgr.live_instances, 0);
	node_cache_slab = kmem_cache_create("node_cache_entry",
						 sizeof(struct node_cache_entry), 0,
						 SLAB_RECLAIM_ACCOUNT, NULL);
	if (!node_cache_slab)
		return -ENOMEM;
	node_cache_pool = zs_create_pool("node_cache_pool");
	if (!node_cache_pool)
		goto err_slab;
	node_cache_buf = alloc_percpu(struct node_cache_cpu);
	if (!node_cache_buf)
		goto err_pool;
	for_each_possible_cpu(cpu) {
		struct node_cache_cpu *buf = per_cpu_ptr(node_cache_buf, cpu);

		buf->compressed = kmalloc(PAGE_SIZE, GFP_KERNEL);
		buf->workspace = kvmalloc(LZ4_MEM_COMPRESS, GFP_KERNEL);
		if (!buf->compressed || !buf->workspace)
			goto err_cpu;
	}
	node_cache_shrinker = shrinker_alloc(0, "f2fs-node-cache");
	if (!node_cache_shrinker)
		goto err_cpu;
	node_cache_shrinker->count_objects = node_cache_shrink_count;
	node_cache_shrinker->scan_objects = node_cache_shrink_scan;
	shrinker_register(node_cache_shrinker);
	ret = sysfs_create_group(kernel_kobj, &node_cache_attr_group);
	if (ret)
		goto err_shrinker;
	ret = register_trace_android_vh_remove_mapping(vh_remove_mapping, NULL);
	if (ret)
		goto err_sysfs;
	ret = register_trace_android_vh_remove_mapping_failed(
			vh_remove_mapping_failed, NULL);
	if (ret)
		goto err_hook1;
	ret = register_trace_android_vh_filemap_get_folio_end(
			vh_filemap_get_folio_end, NULL);
	if (ret)
		goto err_hook2;
	ret = register_trace_android_vh_do_new_mount_fc(vh_do_new_mount_fc, NULL);
	if (ret)
		goto err_hook3;
	ret = register_trace_android_vh_put_super(vh_put_super, NULL);
	if (ret)
		goto err_hook4;
	node_cache_attach_existing();
	pr_info("initialized\n");
	return 0;

err_hook4:
	unregister_trace_android_vh_do_new_mount_fc(vh_do_new_mount_fc, NULL);
err_hook3:
	unregister_trace_android_vh_filemap_get_folio_end(vh_filemap_get_folio_end,
								NULL);
err_hook2:
	unregister_trace_android_vh_remove_mapping_failed(
					vh_remove_mapping_failed, NULL);
err_hook1:
	unregister_trace_android_vh_remove_mapping(vh_remove_mapping, NULL);
err_sysfs:
	sysfs_remove_group(kernel_kobj, &node_cache_attr_group);
err_shrinker:
	shrinker_free(node_cache_shrinker);
	node_cache_shrinker = NULL;
err_cpu:
	for_each_possible_cpu(cpu) {
		struct node_cache_cpu *buf = per_cpu_ptr(node_cache_buf, cpu);

		kvfree(buf->workspace);
		kfree(buf->compressed);
		buf->workspace = NULL;
		buf->compressed = NULL;
	}
	free_percpu(node_cache_buf);
	node_cache_buf = NULL;
err_pool:
	zs_destroy_pool(node_cache_pool);
	node_cache_pool = NULL;
err_slab:
	kmem_cache_destroy(node_cache_slab);
	node_cache_slab = NULL;
	return ret;
}
fs_initcall(node_cache_init);
