const router = require('express').Router();
const auth   = require('../middleware/auth');
const Gear   = require('../models/Gear');

router.use(auth);

router.get('/', async (req, res) => {
  try {
    const items = await Gear.find({ userId: req.user.id }).sort({ createdAt: 1 });
    res.json(items);
  } catch { res.status(500).json({ error: 'Server error' }); }
});

router.post('/', async (req, res) => {
  try {
    const { name, category, weight, qty, notes } = req.body;
    if (!name?.trim()) return res.status(400).json({ error: 'Name required' });
    const item = await Gear.create({ userId: req.user.id, name: name.trim(), category, weight, qty, notes });
    res.status(201).json(item);
  } catch { res.status(500).json({ error: 'Server error' }); }
});

router.put('/:id', async (req, res) => {
  try {
    const item = await Gear.findOneAndUpdate(
      { _id: req.params.id, userId: req.user.id },
      req.body,
      { new: true }
    );
    if (!item) return res.status(404).json({ error: 'Not found' });
    res.json(item);
  } catch { res.status(500).json({ error: 'Server error' }); }
});

router.delete('/:id', async (req, res) => {
  try {
    const item = await Gear.findOneAndDelete({ _id: req.params.id, userId: req.user.id });
    if (!item) return res.status(404).json({ error: 'Not found' });
    res.json({ ok: true });
  } catch { res.status(500).json({ error: 'Server error' }); }
});

module.exports = router;
