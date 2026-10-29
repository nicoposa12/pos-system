# Product Requirements Document (PRD): Mini-Store POS System

## 1. Project Overview
The **Mini-Store Point of Sale (POS) System** is a mobile-first, offline-capable application designed for small convenience stores ("tindahan"). It enables store owners to manage inventory, process sales transactions, and track daily performance without requiring an internet connection.

## 2. Objectives
- Provide a fast and reliable checkout experience.
- Automate inventory tracking to prevent "out-of-stock" or "over-stock" scenarios.
- Offer clear insights into daily sales and income.
- Ensure 100% offline functionality using local storage.

## 3. Technology Stack
- **Frontend Framework:** Flutter (Dart)
- **Database:** SQLite (via `sqflite` package)
- **State Management:** Provider or Riverpod
- **Design System:** Material Design 3

## 4. Functional Requirements

### 4.1. Dashboard
- **Sales Summary:** Display total sales and income for the current day.
- **Transaction Count:** Show the number of successful transactions today.
- **Low Stock Alerts:** Visual indicators for products below a defined threshold.
- **Quick Actions:** Buttons for "New Sale" and "Add Product".

### 4.2. Product Management (CRUD)
- **Add Product:** Create new entries with name, price, stock quantity, and optional barcode.
- **Edit Product:** Update existing product details.
- **Delete Product:** Remove products from the inventory.
- **Product List:** View all products with real-time search functionality.

### 4.3. Sales / POS Screen
- **Product Selection:** Search by name or (optional) barcode scan.
- **Cart Management:** 
    - Add items to a virtual cart.
    - Adjust quantities (increment/decrement).
    - Remove items from cart.
- **Calculation:** Auto-compute total amount and subtotal.
- **Checkout:** Finalize transaction, deduct stock from inventory, and save to transaction history.
- **Discount:** Optional field to apply a flat discount to the total.

### 4.4. Transaction History
- **History List:** Chronological list of all past sales.
- **Transaction Details:** View specific items sold, quantities, and subtotal per item within a transaction.
- **Filtering:** Filter records by date range.

### 4.5. Inventory Management
- **Stock Tracking:** Real-time stock level updates.
- **Auto-Deduction:** Automatically reduce stock levels upon successful checkout.
- **Stock Validation:** Prevent sales if quantity exceeds available stock (negative stock prevention).

## 5. Database Schema (SQLite)

### `products` Table
| Column | Type | Description |
| :--- | :--- | :--- |
| `id` | INTEGER (PK) | Unique product identifier |
| `name` | TEXT | Name of the product |
| `price` | REAL | Unit price |
| `stock` | INTEGER | Current quantity on hand |
| `barcode` | TEXT (NULL) | Optional barcode string |
| `created_at` | DATETIME | Timestamp of creation |

### `transactions` Table
| Column | Type | Description |
| :--- | :--- | :--- |
| `id` | INTEGER (PK) | Unique transaction identifier |
| `total_amount`| REAL | Total amount paid |
| `discount` | REAL | Total discount applied |
| `date` | DATETIME | Timestamp of the sale |

### `transaction_items` Table
| Column | Type | Description |
| :--- | :--- | :--- |
| `id` | INTEGER (PK) | Unique record identifier |
| `transaction_id`| INTEGER (FK) | Reference to transactions table |
| `product_id` | INTEGER (FK) | Reference to products table |
| `quantity` | INTEGER | Units sold |
| `subtotal` | REAL | Price at time of sale * quantity |

## 6. User Interface & UX
- **Theme:** Clean, modern Material 3 interface.
- **Navigation:** Bottom navigation bar or side drawer for easy access to core modules.
- **Responsiveness:** Optimized for mobile phones (portrait) and tablets.
- **Feedback:** SnackBar notifications for successful actions or errors.

## 7. Additional / Optional Features
- **Barcode Integration:** Use the device camera to scan barcodes for faster checkout.
- **Receipt PDF:** Generate a digital receipt shareable via messaging apps.
- **Sales Analytics:** Simple charts showing weekly/monthly income trends.
- **Admin Lock:** Simple PIN system to protect product management and history.

## 8. Development Phases
1. **Phase 1:** Database setup and Product CRUD.
2. **Phase 2:** POS Screen and Cart logic.
3. **Phase 3:** Transaction History and Dashboard implementation.
4. **Phase 4:** UI Polishing and Inventory alerts.
5. **Phase 5:** Optional features (Barcode, Analytics).
