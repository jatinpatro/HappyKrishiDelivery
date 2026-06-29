const router = require('express').Router();
const c = require('../controllers/productController');
const { authenticate } = require('../middleware/auth');
const { requireRole } = require('../middleware/role');
const multer = require('multer');
const path = require('path');

const storage = multer.diskStorage({
  destination: 'uploads/',
  filename: (req, file, cb) => cb(null, Date.now() + path.extname(file.originalname)),
});
const upload = multer({ storage, limits: { fileSize: 5 * 1024 * 1024 } });

router.get('/categories', c.listCategories);
router.get('/', c.listProducts);
router.get('/:id', c.getProduct);

const db = require('../config/database');

router.post('/categories', authenticate, requireRole('admin'), c.createCategory);
router.delete('/categories/:id', authenticate, requireRole('admin'), c.deleteCategory);
router.patch('/categories/:id/toggle', authenticate, requireRole('admin'), (req, res) => {
  const id = parseInt(req.params.id);
  const cat = db.prepare('SELECT id, is_active FROM categories WHERE id=?').get(id);
  if (!cat) return res.status(404).json({ error: 'Category not found' });
  const newActive = cat.is_active ? 0 : 1;
  db.prepare('UPDATE categories SET is_active=? WHERE id=?').run(newActive, id);
  res.json({ id, is_active: newActive });
});
router.post('/', authenticate, requireRole('admin'), upload.single('image'), c.createProduct);
router.put('/:id', authenticate, requireRole('admin'), upload.single('image'), c.updateProduct);

module.exports = router;
