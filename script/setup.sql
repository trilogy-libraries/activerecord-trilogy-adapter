-- Constructs a database for testing purposes (useful for both local testing and CI builds).
DROP DATABASE IF EXISTS `trilogy_test`;
CREATE DATABASE `trilogy_test` CHARACTER SET utf8;
USE `trilogy_test`;

CREATE TABLE `ar_internal_metadata` (
  `key` VARCHAR(255) NOT NULL PRIMARY KEY,
  `value` VARCHAR(255) NOT NULL,
  `created_at` DATETIME NOT NULL,
  `updated_at` DATETIME NOT NULL
);

CREATE TABLE `users` (
  `id` INT(11) NOT NULL AUTO_INCREMENT PRIMARY KEY,
  `name` VARCHAR(255) NOT NULL,
  `created_at` DATETIME NOT NULL,
  `updated_at` DATETIME NOT NULL
);

CREATE TABLE `posts` (
  `id` INT(11) NOT NULL AUTO_INCREMENT PRIMARY KEY,
  `author_id` INT(11),
  `title` VARCHAR(255) NOT NULL,
  `body` VARCHAR(255) NOT NULL,
  `kind` VARCHAR(255) NOT NULL,
  `created_at` DATETIME NOT NULL,
  `updated_at` DATETIME NOT NULL,
  KEY `index_posts_on_author_id` (`author_id`),
  UNIQUE KEY `index_posts_on_kind` (`kind`)
);
