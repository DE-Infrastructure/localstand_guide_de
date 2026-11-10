select order_item_id from {{ ref('fct_order_items') }}
where refunded_kopecks < 0 or refunded_kopecks > gross_kopecks
   or net_kopecks <> gross_kopecks - refunded_kopecks
