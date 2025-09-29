CREATE TEMPORARY TABLE source_order (
    `order_key` BIGINT,
    `cust_key` INT,
    `total_price` DECIMAL(15, 2),
    `order_date` DATE,
    `order_priority` STRING,
    `clerk` STRING
) WITH (
  'connector' = 'faker',
  'rows-per-second' = '10',
  'number-of-rows' = '10000',
  'fields.order_key.expression' = '#{number.numberBetween ''0'',''100000000''}',
  'fields.cust_key.expression' = '#{number.numberBetween ''0'',''20''}',
  'fields.total_price.expression' = '#{number.randomDouble ''3'',''1'',''1000''}',
  'fields.order_date.expression' = '#{date.past ''100'' ''DAYS''}',
  'fields.order_priority.expression' = '#{regexify ''(low|medium|high){1}''}',
  'fields.clerk.expression' = '#{regexify ''(Clerk1|Clerk2|Clerk3|Clerk4){1}''}'
);

CREATE TEMPORARY TABLE source_customer (
    `cust_key` INT,
    `name` STRING,
    `phone` STRING,
    `nation_key` INT NOT NULL,
    `acctbal` DECIMAL(15, 2),
    `mktsegment` STRING,
    PRIMARY KEY (`cust_key`) NOT ENFORCED
) WITH (
  'connector' = 'faker',
  'number-of-rows' = '200',
  'fields.cust_key.expression' = '#{number.numberBetween ''0'',''20''}',
  'fields.name.expression' = '#{funnyName.name}',
  'fields.nation_key.expression' = '#{number.numberBetween ''1'',''5''}',
  'fields.phone.expression' = '#{phoneNumber.cellPhone}',
  'fields.acctbal.expression' = '#{number.randomDouble ''3'',''1'',''1000''}',
  'fields.mktsegment.expression' = '#{regexify ''(AUTOMOBILE|BUILDING|FURNITURE|MACHINERY|HOUSEHOLD){1}''}'
);

CREATE TEMPORARY TABLE `source_nation` (
  `nation_key` INT NOT NULL,
  `name`       STRING,
   PRIMARY KEY (`nation_key`) NOT ENFORCED
) WITH (
  'connector' = 'faker',
  'number-of-rows' = '100',
  'fields.nation_key.expression' = '#{number.numberBetween ''1'',''5''}',
  'fields.name.expression' = '#{regexify ''(CANADA|JORDAN|CHINA|UNITED|INDIA){1}''}'
);

SET 'table.exec.sink.not-null-enforcer'='DROP';