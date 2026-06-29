const db = require('../config/database');
const path = require('path');
const fs = require('fs');

function listCategories(req, res) {
  const cats = db.prepare('SELECT id, name, name_odia, icon, image_url, sort_order FROM categories WHERE is_active = 1 ORDER BY sort_order').all();
  res.json({ categories: cats });
}

function listProducts(req, res) {
  const { category_id, search, page = 1, limit = 20 } = req.query;
  const offset = (parseInt(page) - 1) * parseInt(limit);

  let where = 'p.is_active = 1 AND (p.category_id IS NULL OR c.is_active = 1)';
  const params = [];

  if (category_id) { where += ' AND p.category_id = ?'; params.push(category_id); }
  if (search) { where += ' AND (p.name LIKE ? OR p.name_odia LIKE ?)'; params.push(`%${search}%`, `%${search}%`); }

  const products = db.prepare(`
    SELECT p.*, c.name as category_name, c.name_odia as category_name_odia
    FROM products p
    LEFT JOIN categories c ON c.id = p.category_id
    WHERE ${where}
    ORDER BY p.name
    LIMIT ? OFFSET ?
  `).all(...params, parseInt(limit), offset);

  const total = db.prepare(`
    SELECT COUNT(*) as c FROM products p
    LEFT JOIN categories c ON c.id = p.category_id
    WHERE ${where}
  `).get(...params).c;
  res.json({ products, total, page: parseInt(page), limit: parseInt(limit) });
}

function getProduct(req, res) {
  const product = db.prepare(`
    SELECT p.*, c.name as category_name FROM products p
    LEFT JOIN categories c ON c.id = p.category_id
    WHERE p.id = ? AND p.is_active = 1
  `).get(req.params.id);
  if (!product) return res.status(404).json({ error: 'Product not found' });
  res.json({ product });
}

function createProduct(req, res) {
  const { category_id, name, name_odia, description, unit, price_per_unit, stock_qty, low_stock_threshold, is_weight_adjusted, min_qty, qty_step } = req.body;
  if (!name || !price_per_unit) return res.status(400).json({ error: 'name and price_per_unit required' });

  const image_url = req.file ? `/uploads/${req.file.filename}` : null;
  const result = db.prepare(`
    INSERT INTO products (category_id, name, name_odia, description, unit, price_per_unit, stock_qty, low_stock_threshold, is_weight_adjusted, image_url, min_qty, qty_step)
    VALUES (?,?,?,?,?,?,?,?,?,?,?,?)
  `).run(category_id || null, name, name_odia || null, description || null, unit || 'kg',
    parseFloat(price_per_unit), parseFloat(stock_qty || 0), parseFloat(low_stock_threshold || 5),
    is_weight_adjusted ? 1 : 0, image_url,
    parseFloat(min_qty || 0.5), parseFloat(qty_step || 0.5));

  const product = db.prepare('SELECT * FROM products WHERE id = ?').get(result.lastInsertRowid);
  res.status(201).json({ product });
}

function updateProduct(req, res) {
  const existing = db.prepare('SELECT * FROM products WHERE id = ?').get(req.params.id);
  if (!existing) return res.status(404).json({ error: 'Product not found' });

  const { category_id, name, name_odia, description, unit, price_per_unit, stock_qty, low_stock_threshold, is_weight_adjusted, is_active, min_qty, qty_step } = req.body;
  const image_url = req.file ? `/uploads/${req.file.filename}` : existing.image_url;

  db.prepare(`
    UPDATE products SET category_id=?, name=?, name_odia=?, description=?, unit=?,
    price_per_unit=?, stock_qty=?, low_stock_threshold=?, is_weight_adjusted=?, image_url=?, is_active=?,
    min_qty=?, qty_step=?
    WHERE id=?
  `).run(
    category_id ?? existing.category_id,
    name ?? existing.name, name_odia ?? existing.name_odia,
    description ?? existing.description, unit ?? existing.unit,
    price_per_unit != null ? parseFloat(price_per_unit) : existing.price_per_unit,
    stock_qty != null ? parseFloat(stock_qty) : existing.stock_qty,
    low_stock_threshold != null ? parseFloat(low_stock_threshold) : existing.low_stock_threshold,
    is_weight_adjusted != null ? (is_weight_adjusted ? 1 : 0) : existing.is_weight_adjusted,
    image_url,
    is_active != null ? (is_active ? 1 : 0) : existing.is_active,
    min_qty != null ? parseFloat(min_qty) : (existing.min_qty ?? 0.5),
    qty_step != null ? parseFloat(qty_step) : (existing.qty_step ?? 0.5),
    req.params.id
  );

  res.json({ product: db.prepare('SELECT * FROM products WHERE id = ?').get(req.params.id) });
}

function createCategory(req, res) {
  const { name, name_odia, icon, sort_order } = req.body;
  if (!name) return res.status(400).json({ error: 'name required' });
  const result = db.prepare('INSERT INTO categories (name, name_odia, icon, sort_order) VALUES (?,?,?,?)').run(name, name_odia || null, icon || null, sort_order || 0);
  res.status(201).json({ category: db.prepare('SELECT * FROM categories WHERE id = ?').get(result.lastInsertRowid) });
}

function deleteCategory(req, res) {
  const id = parseInt(req.params.id);
  const existing = db.prepare('SELECT id FROM categories WHERE id = ?').get(id);
  if (!existing) return res.status(404).json({ error: 'Category not found' });
  // Unlink products from this category first
  db.prepare('UPDATE products SET category_id = NULL WHERE category_id = ?').run(id);
  db.prepare('DELETE FROM categories WHERE id = ?').run(id);
  res.json({ message: 'Category deleted' });
}

module.exports = { listCategories, listProducts, getProduct, createProduct, updateProduct, createCategory, deleteCategory };
