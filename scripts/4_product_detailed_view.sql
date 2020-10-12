# Copyright 2020 Google LLC..
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

-- Creates a latest snapshot view of products combined with performance metrics.
CREATE OR REPLACE VIEW
  `{project_id}.{dataset}.product_detailed` AS
WITH
  ProductIssuesTable AS (
    SELECT
      merchant_id,
      unique_product_id,
      MAX(IF(LOWER(servability) = 'disapproved', FALSE, TRUE)) AS has_disapproval_issues,
      MAX(IF(LOWER(servability) = 'demoted', TRUE, FALSE)) AS is_demoted,
      STRING_AGG(IF(LOWER(servability) = 'disapproved', short_description, NULL), ", ") AS disapproval_issues,
      STRING_AGG(IF(LOWER(servability) = 'demoted', short_description, NULL), ", ") demotion_issues,
      STRING_AGG(IF(LOWER(servability) = 'unaffected', short_description, NULL), ", ") warning_issues
    FROM (
      SELECT
        merchant_id,
        product_id,
        servability,
        short_description,
      FROM
      `{project_id}.{dataset}.product_view_{merchant_id}` product_view
      JOIN product_view.issues
    )
    GROUP BY 1,2),
  ProductData AS (
  SELECT
    COALESCE(product_view.aggregator_id, product_view.merchant_id) AS account_id,
    MAX(customer_view.accountdescriptivename) AS account_display_name,
    product_view.merchant_id AS sub_account_id,
    product_view.unique_product_id,
    MAX(product_view.offer_id) AS offer_id,
    MAX(product_view.channel) AS channel,
    MAX(product_view.in_stock) AS in_stock,
    # An offer is labeled as approved when able to serve on all destinations
    MAX(CASE
        WHEN LOWER(destinations.status) <> 'approved' THEN 0
      ELSE
      1
    END
      ) AS is_approved,
    # Aggregated Issues & Servability Statuses
    MAX(CAST(IFNULL(has_disapproval_issues, FALSE) as INT64)) AS has_disapproval_issues,
    MAX(CAST(IFNULL(has_demotion_issues, FALSE) as INT64)) AS has_demotion_issues,
    MAX(disapproval_issues) as agg_disapproval_issues,
    MAX(demotion_issues) as agg_demotion_issues,
    MAX(warning_issues) as agg_warning_issues,
    MIN(IF(TargetedProduct.product_id IS NULL, 0, 1)) AS is_targeted,
    MAX(title) AS title,
    MAX(link) AS item_url,
    MAX(product_type_l1) AS product_type_l1,
    MAX(product_type_l2) AS product_type_l2,
    MAX(product_type_l3) AS product_type_l3,
    MAX(product_type_l4) AS product_type_l4,
    MAX(product_type_l5) AS product_type_l5,
    MAX(google_product_category_l1) AS google_product_category_l1,
    MAX(google_product_category_l2) AS google_product_category_l2,
    MAX(google_product_category_l3) AS google_product_category_l3,
    MAX(google_product_category_l4) AS google_product_category_l4,
    MAX(google_product_category_l5) AS google_product_category_l5,
    MAX(custom_labels.label_0) AS custom_label_0,
    MAX(custom_labels.label_1) AS custom_label_1,
    MAX(custom_labels.label_2) AS custom_label_2,
    MAX(custom_labels.label_3) AS custom_label_3,
    MAX(custom_labels.label_4) AS custom_label_4,
    MAX(product_view.brand) AS brand,
    MAX(product_metrics_view.impressions_30_days) AS impressions_30_days,
    MAX(product_metrics_view.clicks_30_days) AS clicks_30_days,
    MAX(product_metrics_view.cost_30_days) AS cost_30_days,
    MAX(product_metrics_view.conversions_30_days) AS conversions_30_days,
    MAX(product_metrics_view.conversions_value_30_days) AS conversions_value_30_days,
    MAX(description) AS description,
    MAX(mobile_link) AS mobile_link,
    MAX(image_link) AS image_link,
    ANY_VALUE(additional_image_links) AS additional_image_links,
    MAX(content_language) AS content_language,
    MAX(target_country) AS target_country,
    MAX(expiration_date) AS expiration_date,
    MAX(google_expiration_date) AS google_expiration_date,
    MAX(adult) AS adult,
    MAX(age_group) AS age_group,
    MAX(availability) AS availability,
    MAX(availability_date) AS availability_date,
    MAX(color) AS color,
    MAX(condition) AS condition,
    MAX(gender) AS gender,
    MAX(gtin) AS gtin,
    MAX(item_group_id) AS item_group_id,
    MAX(material) AS material,
    MAX(mpn) AS mpn,
    MAX(pattern) AS pattern,
    ANY_VALUE(price) AS price,
    ANY_VALUE(sale_price) AS sale_price,
    ANY_VALUE(additional_product_types) AS additional_product_types,
    ANY_VALUE(issues) AS issues
  FROM
    `{project_id}.{dataset}.product_view_{merchant_id}` product_view,
    UNNEST(destinations) AS destinations
  LEFT JOIN
    ProductIssuesTable
  ON
    ProductIssuesTable.merchant_id = product_view.merchant_id
    AND ProductIssuesTable.unique_product_id = product_view.unique_product_id
  LEFT JOIN
    `{project_id}.{dataset}.product_metrics_view` product_metrics_view
  ON
    product_metrics_view.merchantid = product_view.merchant_id
    AND LOWER(product_metrics_view.product_id) = LOWER(product_view.product_id)
  LEFT JOIN
    `{project_id}.{dataset}.customer_view` customer_view
  ON
    customer_view.externalcustomerid = product_metrics_view.externalcustomerid
  LEFT JOIN
    `{project_id}.{dataset}.TargetedProduct_{external_customer_id}` TargetedProduct
  ON
    TargetedProduct.merchant_id = product_view.merchant_id
    AND TargetedProduct.product_id = product_view.product_id
  GROUP BY
    account_id,
    product_view.merchant_id,
    product_view.unique_product_id
)
SELECT
  *,
  CASE
    WHEN is_approved = 1 AND in_stock = 1
      THEN 1
    ELSE 0
  END AS funnel_in_stock,
  CASE
    WHEN is_approved = 1 AND in_stock = 1  AND is_targeted = 1
      THEN 1
    ELSE 0
  END AS funnel_targeted,
  CASE
    WHEN
      is_approved = 1
      AND in_stock = 1
      AND is_targeted = 1
      AND impressions_30_days > 0
      THEN 1
    ELSE 0
  END AS funnel_has_impression,
  CASE
    WHEN
      is_approved = 1
      AND in_stock = 1
      AND is_targeted = 1
      AND impressions_30_days > 0
      AND clicks_30_days > 0
      THEN 1
    ELSE 0
  END AS funnel_has_clicks
FROM
  ProductData;
