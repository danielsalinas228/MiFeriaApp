const express = require('express');
const authRoutes = require('./src/routes/auth');
const usersRoutes = require('./src/routes/users');

const app = express();

app.use(express.json());

app.get('/health', (_req, res) => res.json({ ok: true }));

app.use('/api/v1/auth', authRoutes);
app.use('/api/v1/users', usersRoutes);

module.exports = app;
