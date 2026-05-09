const mongoose = require('mongoose');

const packItemSchema = new mongoose.Schema({
  gearId: { type: mongoose.Schema.Types.ObjectId, ref: 'Gear', required: true },
  qty:    { type: Number, default: 1 },
}, { _id: false });

const tripSchema = new mongoose.Schema({
  userId:      { type: mongoose.Schema.Types.ObjectId, ref: 'User', required: true, index: true },
  name:        { type: String, required: true, trim: true },
  destination: { type: String, default: '' },
  startDate:   { type: String, default: '' },
  endDate:     { type: String, default: '' },
  notes:       { type: String, default: '' },
  pack:        { type: [packItemSchema], default: [] },
}, { timestamps: true });

module.exports = mongoose.model('Trip', tripSchema);
