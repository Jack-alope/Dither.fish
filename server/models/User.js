const mongoose = require('mongoose');

const userSchema = new mongoose.Schema({
  username: {
    type: String, required: true, unique: true, trim: true, lowercase: true,
    match: [/^[a-z0-9_-]{3,30}$/, 'Username may only contain letters, numbers, hyphens and underscores (3–30 chars)'],
  },
  // sparse so existing documents without email don't conflict on the unique index
  email:    { type: String, unique: true, sparse: true, trim: true, lowercase: true },
}, { timestamps: true });

module.exports = mongoose.model('User', userSchema);
