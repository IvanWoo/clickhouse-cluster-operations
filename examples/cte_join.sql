select 
    products_distributed.PRODUCT_ID,
    products_distributed.PRODUCT_NAME,
    entity_category_local.CATEGORY
from products_distributed
left join (
    select
        PRODUCT_ID,
        CATEGORY
    from entity_category_local
) AS entity_category_local
ON products_distributed.PRODUCT_ID = entity_category_local.PRODUCT_ID;

