const mongoose = require('mongoose');

const gearSchema = new mongoose.Schema({
  userId:   { type: mongoose.Schema.Types.ObjectId, ref: 'User', required: true, index: true },
  name:     { type: String, required: true, trim: true },
  brand:    { type: String, trim: true, default: '' },
  category: { type: String, trim: true, default: '' },
  weight:   { type: Number, default: null },
  qty:      { type: Number, default: 1 },
  notes:    { type: String, default: '' },
}, { timestamps: true });

module.exports = mongoose.model('Gear', gearSchema);
