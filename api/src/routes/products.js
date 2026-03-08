const express = require('express');
const { body, param, validationResult } = require('express-validator');
const db = require('../db');

const router = express.Router();

// Validation middleware
const validate = (req, res, next) => {
  const errors = validationResult(req);
  if (!errors.isEmpty()) {
    return res.status(400).json({ errors: errors.array() });
  }
  next();
};

const productValidation = [
  body('name').trim().notEmpty().isLength({ max: 255 }).escape(),
  body('description').optional().trim().isLength({ max: 2000 }).escape(),
  body('price').isFloat({ min: 0, max: 999999.99 }),
  body('category').optional().trim().isLength({ max: 100 }).escape(),
  body('in_stock').optional().isBoolean(),
];

// GET /api/products - List all products
router.get('/', async (req, res) => {
  try {
    const { category, in_stock, sort } = req.query;
    let queryText = 'SELECT * FROM products';
    const conditions = [];
    const params = [];

    if (category) {
      params.push(category);
      conditions.push(`category = $${params.length}`);
    }
    if (in_stock !== undefined) {
      params.push(in_stock === 'true');
      conditions.push(`in_stock = $${params.length}`);
    }

    if (conditions.length > 0) {
      queryText += ' WHERE ' + conditions.join(' AND ');
    }

    const validSorts = ['name', 'price', 'created_at'];
    if (sort && validSorts.includes(sort)) {
      queryText += ` ORDER BY ${sort}`;
    } else {
      queryText += ' ORDER BY created_at DESC';
    }

    const { rows } = await db.query(queryText, params);
    res.json({ count: rows.length, products: rows });
  } catch (err) {
    console.error('Error fetching products:', err.message);
    res.status(500).json({ error: 'Failed to fetch products' });
  }
});

// GET /api/products/:id - Get single product
router.get('/:id', param('id').isInt({ min: 1 }), validate, async (req, res) => {
  try {
    const { rows } = await db.query('SELECT * FROM products WHERE id = $1', [req.params.id]);
    if (rows.length === 0) {
      return res.status(404).json({ error: 'Product not found' });
    }
    res.json(rows[0]);
  } catch (err) {
    console.error('Error fetching product:', err.message);
    res.status(500).json({ error: 'Failed to fetch product' });
  }
});

// POST /api/products - Create product
router.post('/', productValidation, validate, async (req, res) => {
  try {
    const { name, description, price, category, in_stock } = req.body;
    const { rows } = await db.query(
      `INSERT INTO products (name, description, price, category, in_stock)
       VALUES ($1, $2, $3, $4, $5) RETURNING *`,
      [name, description || null, price, category || null, in_stock !== false]
    );
    res.status(201).json(rows[0]);
  } catch (err) {
    console.error('Error creating product:', err.message);
    res.status(500).json({ error: 'Failed to create product' });
  }
});

// PUT /api/products/:id - Update product
router.put('/:id', [...productValidation, param('id').isInt({ min: 1 })], validate, async (req, res) => {
  try {
    const { name, description, price, category, in_stock } = req.body;
    const { rows } = await db.query(
      `UPDATE products SET name = $1, description = $2, price = $3, category = $4, 
       in_stock = $5, updated_at = CURRENT_TIMESTAMP
       WHERE id = $6 RETURNING *`,
      [name, description || null, price, category || null, in_stock !== false, req.params.id]
    );
    if (rows.length === 0) {
      return res.status(404).json({ error: 'Product not found' });
    }
    res.json(rows[0]);
  } catch (err) {
    console.error('Error updating product:', err.message);
    res.status(500).json({ error: 'Failed to update product' });
  }
});

// DELETE /api/products/:id - Delete product
router.delete('/:id', param('id').isInt({ min: 1 }), validate, async (req, res) => {
  try {
    const { rows } = await db.query('DELETE FROM products WHERE id = $1 RETURNING *', [req.params.id]);
    if (rows.length === 0) {
      return res.status(404).json({ error: 'Product not found' });
    }
    res.json({ message: 'Product deleted', product: rows[0] });
  } catch (err) {
    console.error('Error deleting product:', err.message);
    res.status(500).json({ error: 'Failed to delete product' });
  }
});

module.exports = router;
