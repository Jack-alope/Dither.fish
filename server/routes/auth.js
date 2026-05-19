const router  = require('express').Router();
const jwt     = require('jsonwebtoken');
const crypto  = require('crypto');
const { Resend } = require('resend');
const User    = require('../models/User');
const OtpCode = require('../models/OtpCode');

// Lazy-initialise so the module can be loaded before env vars are set
let _resend = null;
function getResend() {
  if (!_resend) _resend = new Resend(process.env.RESEND_API_KEY);
  return _resend;
}
const FROM = () => process.env.FROM_EMAIL || 'noreply@dither.fish';

// Letters, numbers, hyphens and underscores only; 3–30 chars
const USERNAME_RE = /^[a-z0-9_-]{3,30}$/;
function validateUsername(raw) {
  const u = raw.trim().toLowerCase();
  if (!USERNAME_RE.test(u))
    return 'Username must be 3–30 characters and may only contain letters, numbers, hyphens and underscores';
  return null; // valid
}

function isAdmin(username) {
  return !!(process.env.ADMIN_USERNAME && username === process.env.ADMIN_USERNAME);
}

function makeToken(user) {
  return jwt.sign(
    { id: user._id, username: user.username },
    process.env.JWT_SECRET,
    { expiresIn: '30d' },
  );
}

function maskEmail(email) {
  const [local, domain] = email.split('@');
  const masked =
    local.length <= 2
      ? local[0] + '***'
      : local[0] + '***' + local[local.length - 1];
  return masked + '@' + domain;
}

function generateCode() {
  return String(crypto.randomInt(100000, 999999));
}

// ── POST /api/auth/request-otp ────────────────────────────────────────────────
// Login:    { login: "username_or_email" }         — finds existing account
// Register: { username: "...", email: "..." }      — creates account
router.post('/request-otp', async (req, res) => {
  try {
    const { login, username, email } = req.body;

    let user;
    let targetEmail;

    if (login?.trim()) {
      // ── Login mode ── find by username or email
      const id = login.trim().toLowerCase();
      user = id.includes('@')
        ? await User.findOne({ email: id })
        : await User.findOne({ username: id });
      if (!user)       return res.status(404).json({ error: 'No account found' });
      if (!user.email) return res.status(400).json({ error: 'No email on file — contact support' });
      targetEmail = user.email;

    } else if (username?.trim() && email?.trim()) {
      // ── Register mode ── create or match existing
      const usernameErr = validateUsername(username);
      if (usernameErr) return res.status(400).json({ error: usernameErr });

      const normalUsername = username.trim().toLowerCase();
      const normalEmail    = email.trim().toLowerCase();
      targetEmail = normalEmail;

      user = await User.findOne({ username: normalUsername });
      if (user) {
        if (user.email && user.email !== normalEmail)
          return res.status(409).json({ error: 'Email does not match our records for that username' });
        if (!user.email) { user.email = normalEmail; await user.save(); }
      } else {
        if (process.env.REGISTRATION_OPEN !== 'true')
          return res.status(403).json({ error: 'Registration is closed' });
        user = await User.create({ username: normalUsername, email: normalEmail });
      }

    } else {
      return res.status(400).json({ error: 'Username or email is required' });
    }

    // Invalidate any existing unused codes for this user
    await OtpCode.deleteMany({ userId: user._id, used: false });

    const code      = generateCode();
    const expiresAt = new Date(Date.now() + 10 * 60 * 1000); // 10 min
    await OtpCode.create({ userId: user._id, code, expiresAt });

    await getResend().emails.send({
      from:    FROM(),
      to:      targetEmail,
      subject: `${code} — your Dither.fish login code`,
      html: `
        <div style="font-family:system-ui,sans-serif;max-width:480px;margin:0 auto">
          <h2 style="color:#2e7d32">Dither.fish</h2>
          <p>Hi <strong>${user.username}</strong>,</p>
          <p>Your login code is:</p>
          <div style="font-size:36px;font-weight:700;letter-spacing:8px;padding:16px 0;color:#1a1a1a">
            ${code}
          </div>
          <p style="color:#666;font-size:14px">This code expires in 10 minutes. If you didn't request this, you can safely ignore this email.</p>
        </div>
      `,
    });

    res.json({ sent: true, maskedEmail: maskEmail(targetEmail), username: user.username });
  } catch (err) {
    console.error('request-otp error:', err);
    res.status(500).json({ error: 'Failed to send code' });
  }
});

// ── POST /api/auth/verify-otp ─────────────────────────────────────────────────
// Body: { username, code }
router.post('/verify-otp', async (req, res) => {
  try {
    const { username, code } = req.body;
    if (!username?.trim() || !code?.trim())
      return res.status(400).json({ error: 'Username and code are required' });

    const user = await User.findOne({ username: username.trim().toLowerCase() });
    if (!user) return res.status(404).json({ error: 'User not found' });

    const otp = await OtpCode.findOne({
      userId:    user._id,
      used:      false,
      expiresAt: { $gt: new Date() },
    }).sort({ createdAt: -1 });

    if (!otp || otp.code !== code.trim())
      return res.status(401).json({ error: 'Invalid or expired code' });

    otp.used = true;
    await otp.save();

    res.json({ token: makeToken(user), username: user.username, isAdmin: isAdmin(user.username) });
  } catch (err) {
    console.error('verify-otp error:', err);
    res.status(500).json({ error: 'Server error' });
  }
});

// ── GET /api/auth/me ──────────────────────────────────────────────────────────
router.get('/me', async (req, res) => {
  try {
    const authHeader = req.headers.authorization;
    if (!authHeader?.startsWith('Bearer ')) return res.status(401).json({ error: 'Unauthorized' });
    const payload = jwt.verify(authHeader.slice(7), process.env.JWT_SECRET);
    const user = await User.findById(payload.id).select('username email');
    if (!user) return res.status(404).json({ error: 'User not found' });
    res.json({ username: user.username, email: user.email || null, isAdmin: isAdmin(user.username) });
  } catch (err) {
    if (err.name === 'JsonWebTokenError') return res.status(401).json({ error: 'Invalid token' });
    res.status(500).json({ error: 'Server error' });
  }
});

// ── PUT /api/auth/username ────────────────────────────────────────────────────
// Body: { newUsername }  — requires JWT
router.put('/username', async (req, res) => {
  try {
    const authHeader = req.headers.authorization;
    if (!authHeader?.startsWith('Bearer ')) return res.status(401).json({ error: 'Unauthorized' });
    const payload = jwt.verify(authHeader.slice(7), process.env.JWT_SECRET);
    const user = await User.findById(payload.id);
    if (!user) return res.status(404).json({ error: 'User not found' });

    const { newUsername } = req.body;
    if (!newUsername?.trim()) return res.status(400).json({ error: 'New username is required' });
    const usernameErr = validateUsername(newUsername);
    if (usernameErr) return res.status(400).json({ error: usernameErr });
    const normalNew = newUsername.trim().toLowerCase();
    if (normalNew === user.username) return res.status(400).json({ error: 'That is already your username' });

    const taken = await User.findOne({ username: normalNew });
    if (taken) return res.status(409).json({ error: 'Username already taken' });

    user.username = normalNew;
    await user.save();

    res.json({ token: makeToken(user), username: user.username, isAdmin: isAdmin(user.username) });
  } catch (err) {
    if (err.name === 'JsonWebTokenError') return res.status(401).json({ error: 'Invalid token' });
    console.error('change-username error:', err);
    res.status(500).json({ error: 'Server error' });
  }
});

// ── PUT /api/auth/email ───────────────────────────────────────────────────────
// Body: { newEmail }  — requires JWT
router.put('/email', async (req, res) => {
  try {
    const authHeader = req.headers.authorization;
    if (!authHeader?.startsWith('Bearer ')) return res.status(401).json({ error: 'Unauthorized' });
    const payload = jwt.verify(authHeader.slice(7), process.env.JWT_SECRET);
    const user = await User.findById(payload.id);
    if (!user) return res.status(404).json({ error: 'User not found' });

    const { newEmail } = req.body;
    if (!newEmail?.trim()) return res.status(400).json({ error: 'New email is required' });
    const normalNew = newEmail.trim().toLowerCase();
    if (normalNew === user.email) return res.status(400).json({ error: 'That is already your email' });

    const taken = await User.findOne({ email: normalNew });
    if (taken) return res.status(409).json({ error: 'Email already in use' });

    user.email = normalNew;
    await user.save();

    res.json({ ok: true, email: user.email });
  } catch (err) {
    if (err.name === 'JsonWebTokenError') return res.status(401).json({ error: 'Invalid token' });
    console.error('change-email error:', err);
    res.status(500).json({ error: 'Server error' });
  }
});

module.exports = router;
