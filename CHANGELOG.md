# Changelog

## 0.1.0 — Mon 26 Oct 2026 (Day 1)

First cut of the Diwali fast-track.

- **Database:** multi-tenant schema with brands (Aryas Cuisine, AHIL), menu with pack-size variants and seasonal collections, customers keyed by phone, orders, payments, status history, platform fee ledger. Row Level Security on every table.
- **Pricing on the server:** `create_order()` checks stock, sold-out items, daily limits, pickup hours, lead time, slot capacity and Diwali pickup dates and cutoff, then computes subtotal, 8.25% tax and the 4% platform fee.
- **Stripe (test mode):** `create-order` opens Stripe Checkout (cards, Apple Pay, Google Pay) with Connect application fee support; `stripe-webhook` marks orders paid, expired or refunded and is safe to replay.
- **Customer app:** brand picker, menu with veg filter and live sold-out, cart, checkout with pickup date/time and remembered details, order status page.
- **Staff app:** email sign-in; order board (New → Preparing → Ready → Picked up) with live updates, new-order chime and late warnings; full-screen kitchen screen; prep list per pickup date; menu sold-out switches and price edits; sales page for owners and managers.
- **Emails (Resend):** receipt after payment, "ready for pickup" when staff mark Ready.
- **Tests:** `supabase/tests/rls_and_orders_test.sql` covers tenant isolation, kitchen staff seeing no money, pricing, Diwali rules, webhook replay and refunds.
- **Seed:** Aryas sample dishes (marked Sample) and the 17 AHIL Diwali items from the flyer.
