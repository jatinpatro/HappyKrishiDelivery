const router = require('express').Router();
const c = require('../controllers/customDeliveryController');
const { authenticate } = require('../middleware/auth');
const { requireRole } = require('../middleware/role');

// Customer routes
router.post('/', authenticate, c.submitRequest);
router.get('/my', authenticate, c.myRequests);

// Admin routes
router.get('/', authenticate, requireRole('admin', 'subadmin'), c.listRequests);
router.post('/:id/approve', authenticate, requireRole('admin', 'subadmin'), c.approveRequest);
router.post('/:id/reject', authenticate, requireRole('admin', 'subadmin'), c.rejectRequest);

// Admin: manage whitelisted pincodes
router.get('/pincodes', authenticate, requireRole('admin', 'subadmin'), c.listWhitelistedPincodes);
router.put('/pincodes/:pincode', authenticate, requireRole('admin', 'subadmin'), c.updateWhitelistedPincode);
router.delete('/pincodes/:pincode', authenticate, requireRole('admin', 'subadmin'), c.removeWhitelistedPincode);

// Tiered delivery rules per pincode
router.get('/pincodes/:pincode/rules', authenticate, requireRole('admin', 'subadmin'), c.listPincodeRules);
router.post('/pincodes/:pincode/rules', authenticate, requireRole('admin', 'subadmin'), c.upsertPincodeRule);
router.put('/pincodes/:pincode/rules/:ruleId', authenticate, requireRole('admin', 'subadmin'), c.upsertPincodeRule);
router.delete('/pincodes/:pincode/rules/:ruleId', authenticate, requireRole('admin', 'subadmin'), c.deletePincodeRule);

// Addresses using this pincode
router.get('/pincodes/:pincode/addresses', authenticate, requireRole('admin', 'subadmin'), c.listPincodeAddresses);

module.exports = router;
