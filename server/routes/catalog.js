const router      = require('express').Router();
const auth        = require('../middleware/auth');
const adminOnly   = require('../middleware/admin');
const CatalogItem = require('../models/CatalogItem');

// All approved items — public browse (auth still required to use the app)
router.get('/', auth, async (req, res) => {
  try {
    const items = await CatalogItem.find({ status: 'approved' }).sort({ category: 1, name: 1 });
    res.json(items);
  } catch { res.status(500).json({ error: 'Server error' }); }
});

// Count of pending items — for admin badge
router.get('/pending-count', auth, adminOnly, async (req, res) => {
  try {
    const count = await CatalogItem.countDocuments({ status: 'pending' });
    res.json({ count });
  } catch { res.status(500).json({ error: 'Server error' }); }
});

// Pending items list — admin only
router.get('/pending', auth, adminOnly, async (req, res) => {
  try {
    const items = await CatalogItem.find({ status: 'pending' })
      .populate('submittedBy', 'username')
      .sort({ createdAt: 1 });
    res.json(items);
  } catch { res.status(500).json({ error: 'Server error' }); }
});

// Suggest a new item — any logged-in user
router.post('/suggest', auth, async (req, res) => {
  try {
    const { name, brand, category, weight, notes } = req.body;
    if (!name?.trim()) return res.status(400).json({ error: 'Name required' });
    const item = await CatalogItem.create({
      name: name.trim(), brand: brand?.trim() || '', category: category?.trim() || '',
      weight: weight ?? null, notes: notes?.trim() || '',
      status: 'pending', submittedBy: req.user.id,
    });
    res.status(201).json(item);
  } catch { res.status(500).json({ error: 'Server error' }); }
});

// Edit any catalog item (pending or approved) — admin only
router.put('/:id', auth, adminOnly, async (req, res) => {
  try {
    const { name, brand, category, weight, notes } = req.body;
    if (!name?.trim()) return res.status(400).json({ error: 'Name required' });
    const item = await CatalogItem.findByIdAndUpdate(
      req.params.id,
      { name: name.trim(), brand: brand?.trim() || '', category: category?.trim() || '', weight: weight ?? null, notes: notes?.trim() || '' },
      { new: true }
    );
    if (!item) return res.status(404).json({ error: 'Not found' });
    res.json(item);
  } catch { res.status(500).json({ error: 'Server error' }); }
});

// Approve — admin only
router.put('/:id/approve', auth, adminOnly, async (req, res) => {
  try {
    const item = await CatalogItem.findByIdAndUpdate(
      req.params.id, { status: 'approved' }, { new: true }
    );
    if (!item) return res.status(404).json({ error: 'Not found' });
    res.json(item);
  } catch { res.status(500).json({ error: 'Server error' }); }
});

// Reject/delete — admin only
router.delete('/:id', auth, adminOnly, async (req, res) => {
  try {
    const item = await CatalogItem.findByIdAndDelete(req.params.id);
    if (!item) return res.status(404).json({ error: 'Not found' });
    res.json({ ok: true });
  } catch { res.status(500).json({ error: 'Server error' }); }
});

module.exports = router;
