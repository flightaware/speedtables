-- $Id$

CREATE TABLE passwd (
    user	varstr PRIMARY KEY,
    passwd	varstr,
    uid		integer NOT NULL,
    gid 	integer NOT NULL,
    fullname	varstr,
    home	varstr NOT NULL,
    shell	varstr
);

CREATE TABLE group (
    group	varstr PRIMARY KEY,
    passwd	varstr,
    gid		integer NOT NULL,
    users	varstr
);

