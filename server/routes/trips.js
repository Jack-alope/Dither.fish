const router = require('express').Router();
const auth   = require('../middleware/auth');
const Trip   = require('../models/Trip');

router.use(auth);

router.get('/', async (req, res) => {
  try {
    const trips = await Trip.find({ userId: req.user.id }).sort({ createdAt: 1 });
    res.json(trips);
  } catch { res.status(500).json({ error: 'Server error' }); }
});

router.post('/', async (req, res) => {
  try {
    const { name, destination, startDate, endDate, notes } = req.body;
    if (!name?.trim()) return res.status(400).json({ error: 'Name required' });
    const trip = await Trip.create({ userId: req.user.id, name: name.trim(), destination, startDate, endDate, notes, pack: [] });
    res.status(201).json(trip);
  } catch { res.status(500).json({ error: 'Server error' }); }
});

router.put('/:id', async (req, res) => {
  try {
    const trip = await Trip.findOneAndUpdate(
      { _id: req.params.id, userId: req.user.id },
      req.body,
      { new: true }
    );
    if (!trip) return res.status(404).json({ error: 'Not found' });
    res.json(trip);
  } catch { res.status(500).json({ error: 'Server error' }); }
});

router.delete('/:id', async (req, res) => {
  try {
    const trip = await Trip.findOneAndDelete({ _id: req.params.id, userId: req.user.id });
    if (!trip) return res.status(404).json({ error: 'Not found' });
    res.json({ ok: true });
  } catch { res.status(500).json({ error: 'Server error' }); }
});

module.exports = router;
