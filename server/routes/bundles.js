const router = require('express').Router();
const auth   = require('../middleware/auth');
const Bundle = require('../models/Bundle');

router.use(auth);

router.get('/', async (req, res) => {
  try {
    const items = await Bundle.find({ userId: req.user.id }).sort({ createdAt: 1 });
    res.json(items);
  } catch { res.status(500).json({ error: 'Server error' }); }
});

router.post('/', async (req, res) => {
  try {
    const { name } = req.body;
    if (!name?.trim()) return res.status(400).json({ error: 'Name required' });
    const bundle = await Bundle.create({ userId: req.user.id, name: name.trim(), items: [] });
    res.status(201).json(bundle);
  } catch { res.status(500).json({ error: 'Server error' }); }
});

router.put('/:id', async (req, res) => {
  try {
    const bundle = await Bundle.findOneAndUpdate(
      { _id: req.params.id, userId: req.user.id },
      { name: req.body.name, items: req.body.items },
      { new: true }
    );
    if (!bundle) return res.status(404).json({ error: 'Not found' });
    res.json(bundle);
  } catch { res.status(500).json({ error: 'Server error' }); }
});

router.delete('/:id', async (req, res) => {
  try {
    const bundle = await Bundle.findOneAndDelete({ _id: req.params.id, userId: req.user.id });
    if (!bundle) return res.status(404).json({ error: 'Not found' });
    res.json({ ok: true });
  } catch { res.status(500).json({ error: 'Server error' }); }
});

module.exports = router;
