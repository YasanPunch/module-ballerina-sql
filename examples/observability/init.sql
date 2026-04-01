-- Schema and seed data for the Observability example.
-- Targets MSSQL.

CREATE TABLE Students (
    id          INT IDENTITY(1,1) PRIMARY KEY,
    first_name  VARCHAR(50)  NOT NULL,
    last_name   VARCHAR(50)  NOT NULL,
    age         INT          NOT NULL
);

INSERT INTO Students (first_name, last_name, age) VALUES ('Alice',   'Johnson', 22);
INSERT INTO Students (first_name, last_name, age) VALUES ('Bob',     'Smith',   25);
INSERT INTO Students (first_name, last_name, age) VALUES ('Charlie', 'Brown',   20);
INSERT INTO Students (first_name, last_name, age) VALUES ('Diana',   'Prince',  23);
INSERT INTO Students (first_name, last_name, age) VALUES ('Eve',     'Davis',   21);
