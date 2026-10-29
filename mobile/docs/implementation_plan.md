# Implementation Plan: Mini-Store POS System

This document outlines the step-by-step implementation strategy for the Mini-Store POS system based on the [PRD](file:///c:/Users/basco/mini_store/docs/prd.md).

## Phase 1: Project Foundation & Database Setup
**Goal:** Establish the project structure and local storage capability.

### 1.1 Project Initialization
- [ ] Initialize Flutter project.
- [ ] Add dependencies to `pubspec.yaml`:
    - `sqflite` & `path`: For SQLite integration.
    - `provider` or `flutter_riverpod`: For state management.
    - `intl`: For date and currency formatting.
    - `uuid`: For generating unique transaction IDs if needed.
- [ ] Set up folder structure:
    ```text
    lib/
    ├── core/          # Constants, themes, utils
    ├── data/          # SQLite helper, repositories
    ├── models/        # Product, Transaction, TransactionItem
    ├── providers/     # State management classes
    ├── screens/       # UI layers (Dashboard, POS, Products, History)
    └── widgets/       # Reusable UI components
    ```

### 1.2 Data Modeling
- [ ] Create `Product` model.
- [ ] Create `Transaction` model.
- [ ] Create `TransactionItem` model.

### 1.3 Database Implementation
- [ ] Create `DatabaseHelper` class.
- [ ] Implement `onCreate` logic to initialize tables (`products`, `transactions`, `transaction_items`).
- [ ] Implement CRUD operations for Products.

## Phase 2: Product Management (CRUD)
**Goal:** Enable users to build their store inventory.

- [ ] **UI:** Create "Product List" screen with search.
- [ ] **UI:** Create "Add/Edit Product" modal or screen.
- [ ] **Logic:** Connect UI to `DatabaseHelper` via Provider/Riverpod.
- [ ] **Validation:** Ensure prices and stock quantities are valid numbers.

## Phase 3: POS & Sales Logic
**Goal:** The core functional loop of the application.

- [ ] **State:** Implement a `CartProvider` to manage temporary items before checkout.
- [ ] **UI:** Build the "POS Screen":
    - Product search/selection bar.
    - Scrollable cart list with quantity controls.
    - Total amount display.
- [ ] **Logic:** Checkout process:
    - Validate stock availability.
    - Insert record into `transactions` table.
    - Insert items into `transaction_items` table.
    - **Inventory Update:** Atomically decrement stock in `products` table.

## Phase 4: History & Dashboard
**Goal:** Reporting and analytics.

- [ ] **Transaction History:**
    - List view of all transactions.
    - Detailed view for individual receipts.
    - Date range filtering.
- [ ] **Dashboard Implementation:**
    - Calculate "Daily Total" and "Transaction Count" from the database.
    - Implement "Low Stock" query and display alerts.

## Phase 5: UI Refinement & Polish
**Goal:** Professional look and feel.

- [ ] Implement Material 3 "Slate & Indigo" or similar premium theme.
- [ ] Add animations (page transitions, list item fades).
- [ ] Add SnackBar feedback for actions (e.g., "Item Added to Cart", "Stock Updated").
- [ ] Final testing for edge cases (e.g., empty search results, negative stock attempts).

## Phase 6: Optional Enhancements
- [ ] **Barcode Scanner:** Integrate `mobile_scanner` package.
- [ ] **Receipt Export:** Generate PDF using `pdf` package.
- [ ] **Analytics:** Add simple charts using `fl_chart`.

---

## Technical Considerations
- **Offline-First:** All writes must happen to SQLite first.
- **Data Integrity:** Use SQLite transactions for the checkout process to ensure both the sale is recorded and stock is deducted or neither happens.
- **State Management:** Use `ChangeNotifier` (Provider) or `StateNotifier` (Riverpod) to keep the UI in sync with database changes.
