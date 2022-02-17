
CREATE TABLE `tweet` (
  `id` TEXT,
  `text` TEXT,
  `embed_code` TEXT,
  `place_id` TEXT,
  `author_id` INTEGER,
  `created_at` TEXT,
   UNIQUE(id)
);

CREATE TABLE `place` (
  `id` TEXT,
  `country` TEXT,
  `full_name` TEXT,
  `place_type` TEXT,
  `country_code` TEXT,
  `lat` FLOAT,
  `lng` FLOAT,
  `name` TEXT,
  `type` TEXT,
  `bbox` TEXT,
   UNIQUE(id)
);

