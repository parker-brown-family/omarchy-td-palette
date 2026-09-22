#!/usr/bin/env bash
# A producer that will not take a hint: it traps SIGTERM and keeps writing.
#
# The polite case — a producer that dies on SIGTERM — proves nothing about the
# escalation, because SIGTERM alone already handled it. This is the case the
# SIGKILL exists for, and the case a ceiling that merely asks nicely fails.
trap '' TERM
while :; do
  printf 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA\n'
done
