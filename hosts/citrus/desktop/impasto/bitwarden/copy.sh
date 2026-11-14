#!/bin/sh
set -eu

mode=${1:?}
id=${2:?}
value=""

filter_of() {
  case "$1" in
    notes) printf '%s' '.notes' ;;
    password) printf '%s' '.data.password' ;;
    username) printf '%s' '.data.username' ;;
    cardholder) printf '%s' '.data.cardholder_name' ;;
    card-number) printf '%s' '.data.number' ;;
    card-code) printf '%s' '.data.code' ;;
    identity-email) printf '%s' '.data.email' ;;
    identity-phone) printf '%s' '.data.phone' ;;
    identity-ssn) printf '%s' '.data.ssn' ;;
    identity-passport) printf '%s' '.data.passport_number' ;;
    identity-license) printf '%s' '.data.license_number' ;;
    ssh-private) printf '%s' '.data.private_key' ;;
    ssh-public) printf '%s' '.data.public_key' ;;
    ssh-fingerprint) printf '%s' '.data.fingerprint' ;;
    identity-name) printf '%s' '[.data.title, .data.first_name, .data.middle_name, .data.last_name] | map(select(. != null and . != "")) | join(" ")' ;;
    identity-address) printf '%s' '.data as $d | ([$d.address1, $d.address2, $d.address3] | map(select(. != null and . != ""))) as $first | ([$d.city, $d.state] | map(select(. != null and . != "")) | join(", ")) as $region | ($region + (if ($d.postal_code // "") != "" then (if $region == "" then "" else " " end) + $d.postal_code else "" end)) as $place | ($first + (if $place != "" then [$place] else [] end) + (if ($d.country // "") != "" then [$d.country] else [] end)) | join("\n")' ;;
  esac
}

case "$mode" in
  totp)
    value=$(rbw code "$id")
    ;;
  uri:* | field:* | history:*)
    index=${mode#*:}
    case "$index" in
      '' | *[!0-9]*) exit 2 ;;
    esac
    collection=${mode%%:*}
    if [ "$collection" = "uri" ]; then
      filter=".data.uris[$index].uri"
    elif [ "$collection" = "field" ]; then
      filter=".fields[$index].value"
    else
      filter=".history[$index].password"
    fi
    value=$(rbw get --raw "$id" | jq -r "$filter // \"\"")
    ;;
  *)
    filter=$(filter_of "$mode")
    if [ -z "$filter" ]; then
      exit 2
    fi
    value=$(rbw get --raw "$id" | jq -r "$filter // \"\"")
    ;;
esac

if [ -z "$value" ]; then
  exit 1
fi

printf '%s' "$value" | wl-copy --sensitive --type text/plain
