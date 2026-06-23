const WebSocket = require('ws');
const jwt = require('jsonwebtoken');
const db = require('../config/database');

// Map of orderId -> Set of WebSocket clients
const rooms = new Map();

let wss;

function init(server) {
  wss = new WebSocket.Server({ server });

  wss.on('connection', (ws, req) => {
    const url = new URL(req.url, 'http://localhost');
    const token = url.searchParams.get('token');
    const orderId = url.searchParams.get('order_id');

    if (!token || !orderId) {
      ws.close(4001, 'token and order_id required');
      return;
    }

    let user;
    try {
      const payload = jwt.verify(token, process.env.JWT_SECRET);
      user = db.prepare('SELECT id, role FROM users WHERE id = ?').get(payload.id);
    } catch {
      ws.close(4002, 'Invalid token');
      return;
    }

    if (!user) {
      ws.close(4003, 'User not found');
      return;
    }

    // Add to room
    if (!rooms.has(orderId)) rooms.set(orderId, new Set());
    rooms.get(orderId).add(ws);

    ws.on('close', () => {
      rooms.get(orderId)?.delete(ws);
      if (rooms.get(orderId)?.size === 0) rooms.delete(orderId);
    });

    ws.on('error', () => {});

    ws.send(JSON.stringify({ type: 'connected', order_id: orderId }));
  });
}

function broadcast(orderId, message) {
  const room = rooms.get(String(orderId));
  if (!room) return;
  const data = JSON.stringify(message);
  for (const client of room) {
    if (client.readyState === WebSocket.OPEN) {
      client.send(data);
    }
  }
}

module.exports = { init, broadcast };
