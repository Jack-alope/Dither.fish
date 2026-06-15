// Public, unauthenticated read-only view of a shared trip.
// Returns the trip with resolved gear/bundle snapshots so the client can render
// it through the same read-only ("archived") path without exposing the API.
const router = require('express').Router();
const Trip   = require('../models/Trip');
const Gear   = require('../models/Gear');
const Bundle = require('../models/Bundle');

router.get('/trips/:publicId', async (req, res) => {
  try {
    const trip = await Trip.findOne({ publicId: req.params.publicId, public: true }).lean();
    if (!trip) return res.status(404).json({ error: 'Not found' });

    // Bundles referenced by the trip's packs
    const bundleIds = new Set();
    (trip.packs || []).forEach(pk => (pk.bundleRefs || []).forEach(br => bundleIds.add(String(br.bundleId))));
    const bundleDocs = bundleIds.size
      ? await Bundle.find({ _id: { $in: [...bundleIds] }, userId: trip.userId }).lean()
      : [];

    // Gear referenced directly or via those bundles
    const gearIds = new Set();
    (trip.packs || []).forEach(pk => (pk.items || []).forEach(it => gearIds.add(String(it.gearId))));
    bundleDocs.forEach(b => (b.items || []).forEach(it => gearIds.add(String(it.gearId))));
    const gearDocs = gearIds.size
      ? await Gear.find({ _id: { $in: [...gearIds] }, userId: trip.userId }).lean()
      : [];

    const frozenGear = gearDocs.map(g => ({
      _id: g._id, name: g.name, brand: g.brand || '', category: g.category || '',
      weight: g.weight ?? null, qty: g.qty ?? 1, notes: g.notes || '',
    }));
    const frozenBundles = bundleDocs.map(b => ({
      _id: b._id, name: b.name,
      items: (b.items || []).map(i => ({ gearId: String(i.gearId), qty: i.qty ?? 1 })),
    }));

    // archived:true makes the client render it read-only from the frozen snapshots
    res.json({
      _id: trip._id,
      name: trip.name,
      destination: trip.destination || '',
      startDate: trip.startDate || '',
      endDate: trip.endDate || '',
      notes: trip.notes || '',
      routeNotes: trip.routeNotes || '',
      tracks: trip.tracks || [],
      packs: trip.packs || [],
      public: true,
      archived: true,
      frozenGear,
      frozenBundles,
    });
  } catch { res.status(500).json({ error: 'Server error' }); }
});

module.exports = router;
