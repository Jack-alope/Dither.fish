require('dotenv').config({ path: require('path').join(__dirname, '../.env') });
const express   = require('express');
const mongoose  = require('mongoose');
const cors      = require('cors');
const helmet    = require('helmet');
const rateLimit = require('express-rate-limit');
const path      = require('path');

const app  = express();
const port = process.env.PORT || 3000;
const isProd = process.env.NODE_ENV === 'production';

// Security headers
app.use(helmet({ contentSecurityPolicy: false }));

// CORS — locked to ALLOWED_ORIGIN in production, open in dev
app.use(cors(isProd && process.env.ALLOWED_ORIGIN
  ? { origin: process.env.ALLOWED_ORIGIN, credentials: true }
  : {}
));

// Body size cap
app.use(express.json({ limit: '100kb' }));

// Rate limiting on auth endpoints (20 requests per 15 min per IP)
const authLimiter = rateLimit({
  windowMs: 15 * 60 * 1000,
  max: 20,
  standardHeaders: true,
  legacyHeaders: false,
  message: { error: 'Too many attempts, please try again later' },
});
app.use('/api/auth', authLimiter);

// API routes
app.use('/api/auth',    require('./routes/auth'));
app.use('/api/gear',    require('./routes/gear'));
app.use('/api/trips',   require('./routes/trips'));
app.use('/api/catalog', require('./routes/catalog'));
app.use('/api/bundles', require('./routes/bundles'));

// Serve frontend
app.use(express.static(path.join(__dirname, '..')));
app.get('*', (req, res) => res.sendFile(path.join(__dirname, '../index.html')));

// Start HTTP server immediately so the frontend is always reachable
app.listen(port, () => console.log(`Server running on http://localhost:${port}`));

mongoose
  .connect(process.env.MONGODB_URI)
  .then(() => console.log('Connected to MongoDB'))
  .catch(err => console.error('MongoDB connection error:', err.message));
