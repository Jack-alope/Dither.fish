const mongoose = require('mongoose');

const bundleSchema = new mongoose.Schema({
  userId: { type: mongoose.Schema.Types.ObjectId, ref: 'User', required: true, index: true },
  name:   { type: String, required: true, trim: true },
  items:  [{
    gearId: { type: mongoose.Schema.Types.ObjectId },
    qty:    { type: Number, default: 1, min: 1 },
  }],
}, { timestamps: true });

module.exports = mongoose.model('Bundle', bundleSchema);
