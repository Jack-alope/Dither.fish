const router = require('express').Router();
const jwt    = require('jsonwebtoken');
const User   = require('../models/User');

function isAdmin(username) {
  return !!(process.env.ADMIN_USERNAME && username === process.env.ADMIN_USERNAME);
}

function makeToken(user) {
  return jwt.sign({ id: user._id, username: user.username }, process.env.JWT_SECRET, { expiresIn: '30d' });
}

router.post('/register', async (req, res) => {
  if (process.env.REGISTRATION_OPEN !== 'true')
    return res.status(403).json({ error: 'Registration is closed' });
  try {
    const { username, password } = req.body;
    if (!username?.trim() || !password) return res.status(400).json({ error: 'Username and password required' });
    if (password.length < 8) return res.status(400).json({ error: 'Password must be at least 8 characters' });
    const exists = await User.findOne({ username: username.trim().toLowerCase() });
    if (exists) return res.status(409).json({ error: 'Username already taken' });
    const user = await User.create({ username: username.trim(), password });
    res.status(201).json({ token: makeToken(user), username: user.username, isAdmin: isAdmin(user.username) });
  } catch (err) {
    res.status(500).json({ error: 'Server error' });
  }
});

router.post('/login', async (req, res) => {
  try {
    const { username, password } = req.body;
    const user = await User.findOne({ username: username?.trim().toLowerCase() });
    if (!user || !(await user.verifyPassword(password)))
      return res.status(401).json({ error: 'Invalid username or password' });
    res.json({ token: makeToken(user), username: user.username, isAdmin: isAdmin(user.username) });
  } catch (err) {
    res.status(500).json({ error: 'Server error' });
  }
});

module.exports = router;
