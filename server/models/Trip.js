const mongoose = require('mongoose');

const packItemSchema = new mongoose.Schema({
  gearId:  { type: mongoose.Schema.Types.ObjectId, ref: 'Gear', required: true },
  qty:     { type: Number, default: 1 },
  cubeId:  { type: String, default: null },
  checked: { type: Boolean, default: false },
  type:    { type: String, enum: ['base', 'worn', 'consumable'], default: 'base' },
}, { _id: false });

const cubeSchema = new mongoose.Schema({
  name: { type: String, default: 'Cube', trim: true },
});

const bundleItemTypeSchema = new mongoose.Schema({
  gearId: { type: String },
  type:   { type: String, enum: ['base', 'worn', 'consumable'], default: 'base' },
}, { _id: false });

const bundleRefSchema = new mongoose.Schema({
  bundleId:     { type: mongoose.Schema.Types.ObjectId, ref: 'Bundle', required: true },
  expanded:     { type: Boolean, default: false },
  checkedItems: { type: [String], default: [] },
  itemTypes:    { type: [bundleItemTypeSchema], default: [] },
  cubeId:       { type: String, default: null },
}, { _id: false });

const packSchema = new mongoose.Schema({
  name:       { type: String, default: 'Pack', trim: true },
  cubes:      { type: [cubeSchema], default: [] },
  items:      { type: [packItemSchema], default: [] },
  bundleRefs: { type: [bundleRefSchema], default: [] },
});

// Frozen gear/bundle snapshots stored when a trip is archived
const frozenGearSchema = new mongoose.Schema({
  _id:      { type: mongoose.Schema.Types.ObjectId },
  name:     { type: String },
  brand:    { type: String, default: '' },
  category: { type: String, default: '' },
  weight:   { type: Number, default: null },
  qty:      { type: Number, default: 1 },
  notes:    { type: String, default: '' },
}, { _id: false });

const frozenBundleItemSchema = new mongoose.Schema({
  gearId: { type: String },
  qty:    { type: Number, default: 1 },
}, { _id: false });

const frozenBundleSchema = new mongoose.Schema({
  _id:   { type: mongoose.Schema.Types.ObjectId },
  name:  { type: String },
  items: { type: [frozenBundleItemSchema], default: [] },
}, { _id: false });

// GPX route track for a trip
const trackSchema = new mongoose.Schema({
  id:       { type: String, default: '' },            // client-generated id for keying
  name:     { type: String, default: '' },
  points:   { type: [[Number]], default: undefined }, // [[lat, lon, ele], ...]
  distance: { type: Number, default: null },          // metres
  ascent:   { type: Number, default: null },          // metres of cumulative gain
  bounds:   { type: [Number], default: undefined },   // [minLat, minLon, maxLat, maxLon]
}, { _id: false });

const tripSchema = new mongoose.Schema({
  userId:        { type: mongoose.Schema.Types.ObjectId, ref: 'User', required: true, index: true },
  name:          { type: String, required: true, trim: true },
  destination:   { type: String, default: '' },
  startDate:     { type: String, default: '' },
  endDate:       { type: String, default: '' },
  notes:         { type: String, default: '' },
  pack:          { type: [packItemSchema], default: [] },
  packs:         { type: [packSchema], default: [] },
  archived:      { type: Boolean, default: false },
  public:        { type: Boolean, default: false },     // view-only sharing
  publicId:      { type: String, default: '', index: true }, // unguessable share token
  track:         { type: trackSchema, default: null },  // legacy single track (kept for back-compat)
  tracks:        { type: [trackSchema], default: [] },
  routeNotes:    { type: String, default: '' },         // free-text hike description (days, camping, etc.)
  frozenGear:    { type: [frozenGearSchema], default: null },
  frozenBundles: { type: [frozenBundleSchema], default: null },
}, { timestamps: true });

module.exports = mongoose.model('Trip', tripSchema);
