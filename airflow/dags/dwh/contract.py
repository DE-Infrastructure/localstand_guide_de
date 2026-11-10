"""Explicit extraction columns; keep source and raw schemas in sync."""

TABLES = {
    'students': ('student_id', 'full_name', 'email', 'city', 'acquired_via', 'registered_at', 'updated_at'),
    'courses': ('course_id', 'title', 'category', 'price_kopecks', 'total_lessons', 'updated_at'),
    'orders': ('order_id', 'student_id', 'ordered_at', 'status', 'updated_at'),
    'order_items': ('order_item_id', 'order_id', 'course_id', 'price_kopecks', 'discount_kopecks', 'updated_at'),
    'payments': ('payment_id', 'order_id', 'amount_kopecks', 'status', 'paid_at', 'updated_at'),
    'refunds': ('refund_id', 'order_item_id', 'amount_kopecks', 'status', 'refunded_at', 'updated_at'),
    'enrollments': ('enrollment_id', 'order_item_id', 'enrolled_at', 'updated_at'),
    'lesson_events': ('delivery_id', 'event_id', 'enrollment_id', 'lesson_no', 'event_type', 'event_at', 'received_at'),
}
