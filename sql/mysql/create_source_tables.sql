CREATE DATABASE IF NOT EXISTS bhaskar_retail_db;

USE bhaskar_retail_db;

CREATE TABLE category
(
    ProductCategoryKey INT PRIMARY KEY,
    ProductCategoryLabel VARCHAR(50),
    ProductCategoryName VARCHAR(100)
);

CREATE TABLE subcategory
(
    ProductSubcategoryKey INT PRIMARY KEY,
    ProductSubcategoryLabel VARCHAR(50),
    ProductSubcategoryName VARCHAR(100),
    ProductCategoryKey INT
);

CREATE TABLE product
(
    ProductKey INT PRIMARY KEY,
    ProductName VARCHAR(255),
    ProductSubcategoryKey INT,
    Manufacturer VARCHAR(100),
    BrandName VARCHAR(100),
    ClassID VARCHAR(50),
    ClassName VARCHAR(100),
    StyleID VARCHAR(50),
    StyleName VARCHAR(100),
    ColorID VARCHAR(50),
    ColorName VARCHAR(100)
);