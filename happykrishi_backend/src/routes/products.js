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

router.post('/categories', authenticate, requireRole('admin'), c.createCategory);
router.delete('/categories/:id', authenticate, requireRole('admin'), c.deleteCategory);
router.post('/', authenticate, requireRole('admin'), upload.single('image'), c.createProduct);
router.put('/:id', authenticate, requireRole('admin'), upload.single('image'), c.updateProduct);

module.exports = router;
