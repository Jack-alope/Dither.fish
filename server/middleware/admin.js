module.exports = function (req, res, next) {
  if (!process.env.ADMIN_USERNAME) return res.status(403).json({ error: 'No admin configured' });
  if (req.user?.username !== process.env.ADMIN_USERNAME)
    return res.status(403).json({ error: 'Admin only' });
  next();
};
