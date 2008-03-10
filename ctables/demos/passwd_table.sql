-- $Id$

CREATE TABLE passwd (
    username	varchar PRIMARY KEY,
    passwd	varchar,
    uid		integer NOT NULL,
    gid 	integer NOT NULL,
    fullname	varchar,
    home	varchar NOT NULL,
    shell	varchar
);

