const mongoose = require('mongoose');

const packItemSchema = new mongoose.Schema({
  gearId:  { type: mongoose.Schema.Types.ObjectId, ref: 'Gear', required: true },
  qty:     { type: Number, default: 1 },
  cubeId:  { type: String, default: null },
  checked: { type: Boolean, default: false },
}, { _id: false });

const cubeSchema = new mongoose.Schema({
  name: { type: String, default: 'Cube', trim: true },
});

const packSchema = new mongoose.Schema({
  name:  { type: String, default: 'Pack', trim: true },
  cubes: { type: [cubeSchema], default: [] },
  items: { type: [packItemSchema], default: [] },
});

const tripSchema = new mongoose.Schema({
  userId:      { type: mongoose.Schema.Types.ObjectId, ref: 'User', required: true, index: true },
  name:        { type: String, required: true, trim: true },
  destination: { type: String, default: '' },
  startDate:   { type: String, default: '' },
  endDate:     { type: String, default: '' },
  notes:       { type: String, default: '' },
  pack:        { type: [packItemSchema], default: [] },
  packs:       { type: [packSchema], default: [] },
}, { timestamps: true });

module.exports = mongoose.model('Trip', tripSchema);
