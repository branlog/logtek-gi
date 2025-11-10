-- Enable pgcrypto for digest/hash helpers used by join codes
create extension if not exists pgcrypto with schema public;
