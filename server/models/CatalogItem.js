const mongoose = require('mongoose');

const variantSchema = new mongoose.Schema({
  name:   { type: String, required: true, trim: true },
  weight: { type: Number, default: null },
});

const catalogItemSchema = new mongoose.Schema({
  name:        { type: String, required: true, trim: true },
  brand:       { type: String, trim: true, default: '' },
  category:    { type: String, trim: true, default: '' },
  weight:      { type: Number, default: null },
  notes:       { type: String, default: '' },
  status:      { type: String, enum: ['approved', 'pending'], default: 'pending', index: true },
  submittedBy: { type: mongoose.Schema.Types.ObjectId, ref: 'User', default: null },
  variants:    { type: [variantSchema], default: [] },
}, { timestamps: true });

module.exports = mongoose.model('CatalogItem', catalogItemSchema);
