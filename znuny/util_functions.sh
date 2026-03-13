#!/bin/bash
# Utility logging functions for the Znuny container.

ZNUNY_ASCII_COLOR_BLUE="38;5;31"
ZNUNY_ASCII_COLOR_RED="31"

function print_info() {
  echo -e "[INFO]  $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

function print_warning() {
  echo -e "[WARN]  $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

function print_error() {
  echo -e "[ERROR] $(date '+%Y-%m-%d %H:%M:%S') - $1" >&2
}
