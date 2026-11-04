#!/usr/bin/env python3
"""
review.py — IaC static security scanner.

Scans Terraform/OpenTofu files in platforms/ for security misconfigurations
and writes structured findings to .audits/<audit_id>/gcp-<subsystem>.json.

NOTE: platforms/ is the repo's IaC root directory — it is NOT related to
the -p <platform> flag.  The -p flag controls which cloud-provider check
patterns are applied (e.g. -p gcp runs google_* resource checks).  The scan
always walks all of platforms/ regardless of the -p value.

Uses the same finding JSON schema as audit.py so remediate/refactor tools
can process both audit and review outputs interchangeably.

Usage:
    review.py [-p <platform> ...] [-s <subsystem> ...] [-i <audit_id>]
"""

import argparse
import json
import re
import sys
from datetime import datetime, timezone
from pathlib import Path


SUPPORTED_PLATFORMS = ['gcp']
SUPPORTED_SUBSYSTEMS = ['iam', 'compute', 'network', 'storage', 'functions', 'databases', 'analytics']

SEVERITY_CRITICAL = 'CRITICAL'
SEVERITY_HIGH = 'HIGH'
SEVERITY_MEDIUM = 'MEDIUM'
SEVERITY_INFO = 'INFO'

# Root of the repo where all IaC (.tf) files live.
# This is independent of the -p <platform> flag — it is always scanned in full.
IAC_ROOT = Path('platforms')


# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------

def parse_args():
    parser = argparse.ArgumentParser(
        prog='sectool review',
        description='Scan IaC files in platforms/ for GCP security misconfigurations',
        add_help=True,
    )
    parser.add_argument(
        '-p', dest='platforms', metavar='platform', nargs='+',
        default=SUPPORTED_PLATFORMS,
        help=f'Platform(s) to review (default: all — {SUPPORTED_PLATFORMS})',
    )
    parser.add_argument(
        '-s', dest='subsystems', metavar='subsystem', nargs='+',
        default=SUPPORTED_SUBSYSTEMS,
        help=f'Subsystem(s) to review (default: all — {SUPPORTED_SUBSYSTEMS})',
    )
    parser.add_argument(
        '-i', dest='audit_id', metavar='audit_id', default=None,
        help='Override the generated audit_id (form: YYYYMMDD-HHMMSS-review)',
    )
    parser.add_argument(
        '--check-args', action='store_true',
        help='parse arguments, print them as JSON and exit (no scan, no .audits/ write)',
    )
    return parser.parse_args()


# ---------------------------------------------------------------------------
# IaC file helpers
# ---------------------------------------------------------------------------

def collect_tf_files(root=IAC_ROOT):
    """Return all .tf files under root, relative to CWD."""
    root_path = Path(root)
    if not root_path.exists():
        return []
    return sorted(root_path.rglob('*.tf'))


def read_file(path):
    try:
        return path.read_text(encoding='utf-8')
    except OSError:
        return ''


def find_pattern(content, pattern, flags=re.IGNORECASE):
    """Return list of (line_no, line_text) for lines matching pattern."""
    matches = []
    for i, line in enumerate(content.splitlines(), start=1):
        if re.search(pattern, line, flags):
            matches.append((i, line.strip()))
    return matches


def format_location(file_path, line_no):
    return f'{file_path}:{line_no}'


# ---------------------------------------------------------------------------
# Finding helpers (mirrors audit.py)
# ---------------------------------------------------------------------------

def make_finding(finding_id, severity, title, detail, check_cmd, remediation, status='fail'):
    return {
        'id': finding_id,
        'severity': severity,
        'title': title,
        'detail': detail,
        'check_cmd': check_cmd,
        'remediation': remediation,
        'status': status,
    }


def finding_pass(finding_id, title, check_cmd):
    return make_finding(finding_id, SEVERITY_INFO, title, 'No issues found', check_cmd, '', status='pass')


# ---------------------------------------------------------------------------
# GCP IAM IaC checks
# ---------------------------------------------------------------------------

def check_gcp_iam_iac(tf_files):
    findings = []

    # Check 1: primitive roles in google_project_iam_binding / member
    primitive_roles = ['roles/owner', 'roles/editor', 'roles/viewer']
    pattern = r'roles/(owner|editor|viewer)'
    hits = []
    for f in tf_files:
        content = read_file(f)
        for line_no, line in find_pattern(content, pattern):
            hits.append(f'{format_location(f, line_no)}: {line}')

    if hits:
        detail = '; '.join(hits[:5])
        findings.append(make_finding(
            'gcp-iam-001', SEVERITY_CRITICAL,
            'Primitive IAM role in IaC',
            f'Primitive roles found: {detail}',
            f'grep -rn "roles/owner\\|roles/editor\\|roles/viewer" {IAC_ROOT}/',
            'Replace primitive roles with predefined roles. '
            'Use roles/storage.objectViewer, roles/run.developer, etc. '
            'Never use roles/owner, roles/editor, or roles/viewer.',
        ))
    else:
        findings.append(finding_pass(
            'gcp-iam-001', 'No primitive IAM roles in IaC',
            f'grep -rn "roles/owner\\|roles/editor\\|roles/viewer" {IAC_ROOT}/',
        ))

    # Check 2: allUsers or allAuthenticatedUsers in IAM bindings
    pattern = r'allUsers|allAuthenticatedUsers'
    hits = []
    for f in tf_files:
        content = read_file(f)
        for line_no, line in find_pattern(content, pattern):
            hits.append(f'{format_location(f, line_no)}: {line}')

    if hits:
        detail = '; '.join(hits[:5])
        findings.append(make_finding(
            'gcp-iam-002', SEVERITY_CRITICAL,
            'Public IAM binding (allUsers/allAuthenticatedUsers) in IaC',
            f'Public bindings found: {detail}',
            f'grep -rn "allUsers\\|allAuthenticatedUsers" {IAC_ROOT}/',
            'Remove allUsers and allAuthenticatedUsers from all IAM bindings. '
            'Use specific service accounts or authenticated user groups.',
        ))
    else:
        findings.append(finding_pass(
            'gcp-iam-002', 'No public IAM bindings in IaC',
            f'grep -rn "allUsers\\|allAuthenticatedUsers" {IAC_ROOT}/',
        ))

    # Check 3: default service account references
    pattern = r'compute@developer\.gserviceaccount\.com|@appspot\.gserviceaccount\.com'
    hits = []
    for f in tf_files:
        content = read_file(f)
        for line_no, line in find_pattern(content, pattern):
            hits.append(f'{format_location(f, line_no)}: {line}')

    if hits:
        detail = '; '.join(hits[:5])
        findings.append(make_finding(
            'gcp-iam-003', SEVERITY_HIGH,
            'Default service account referenced in IaC',
            f'Default SA references: {detail}',
            f'grep -rn "compute@developer.gserviceaccount.com" {IAC_ROOT}/',
            'Create a dedicated service account per workload. '
            'The default compute SA has Editor on the project.',
        ))
    else:
        findings.append(finding_pass(
            'gcp-iam-003', 'No default service account references in IaC',
            f'grep -rn "compute@developer.gserviceaccount.com" {IAC_ROOT}/',
        ))

    return findings


# ---------------------------------------------------------------------------
# GCP Compute IaC checks
# ---------------------------------------------------------------------------

def check_gcp_compute_iac(tf_files):
    findings = []

    # Check 1: google_compute_instance with access_config (public IP)
    hits = []
    for f in tf_files:
        content = read_file(f)
        # access_config block with no nat_ip being empty means public ephemeral IP
        if re.search(r'resource\s+"google_compute_instance"', content, re.IGNORECASE):
            for line_no, line in find_pattern(content, r'access_config\s*\{'):
                hits.append(f'{format_location(f, line_no)}: {line}')

    if hits:
        detail = '; '.join(hits[:5])
        findings.append(make_finding(
            'gcp-compute-001', SEVERITY_HIGH,
            'Compute instance with public IP (access_config) in IaC',
            f'Public IP configurations: {detail}',
            f'grep -rn "access_config" {IAC_ROOT}/',
            'Remove access_config blocks from google_compute_instance resources. '
            'Use Cloud NAT for outbound internet and IAP for SSH access.',
        ))
    else:
        findings.append(finding_pass(
            'gcp-compute-001', 'No compute instances with public IPs in IaC',
            f'grep -rn "access_config" {IAC_ROOT}/',
        ))

    # Check 2: enable_oslogin not set to true
    hits = []
    for f in tf_files:
        content = read_file(f)
        if re.search(r'resource\s+"google_compute_instance"', content, re.IGNORECASE):
            if not re.search(r'enable-oslogin\s*=\s*"TRUE"', content, re.IGNORECASE):
                # Find the resource block location
                for line_no, line in find_pattern(content, r'resource\s+"google_compute_instance"'):
                    hits.append(f'{format_location(f, line_no)}: OS Login not enabled')

    if hits:
        detail = '; '.join(hits[:5])
        findings.append(make_finding(
            'gcp-compute-002', SEVERITY_MEDIUM,
            'Compute instance without OS Login in IaC',
            f'Instances missing OS Login: {detail}',
            f'grep -rn "google_compute_instance" {IAC_ROOT}/',
            'Add OS Login to metadata in google_compute_instance: '
            'metadata = { enable-oslogin = "TRUE" }',
        ))
    else:
        findings.append(finding_pass(
            'gcp-compute-002', 'All compute instances have OS Login in IaC',
            f'grep -rn "google_compute_instance" {IAC_ROOT}/',
        ))

    return findings


# ---------------------------------------------------------------------------
# GCP Network IaC checks
# ---------------------------------------------------------------------------

def check_gcp_network_iac(tf_files):
    findings = []

    # Check 1: firewall rules with source_ranges 0.0.0.0/0
    hits = []
    for f in tf_files:
        content = read_file(f)
        if re.search(r'resource\s+"google_compute_firewall"', content, re.IGNORECASE):
            for line_no, line in find_pattern(content, r'0\.0\.0\.0/0'):
                hits.append(f'{format_location(f, line_no)}: {line}')

    if hits:
        detail = '; '.join(hits[:5])
        findings.append(make_finding(
            'gcp-network-001', SEVERITY_CRITICAL,
            'Firewall rule open to 0.0.0.0/0 in IaC',
            f'World-open firewall rules: {detail}',
            f'grep -rn "0.0.0.0/0" {IAC_ROOT}/',
            'Replace 0.0.0.0/0 source_ranges with specific CIDR ranges. '
            'For SSH, use IAP range 35.235.240.0/20 only.',
        ))
    else:
        findings.append(finding_pass(
            'gcp-network-001', 'No 0.0.0.0/0 firewall rules in IaC',
            f'grep -rn "0.0.0.0/0" {IAC_ROOT}/',
        ))

    # Check 2: Cloud SQL with ipv4_enabled = true
    hits = []
    for f in tf_files:
        content = read_file(f)
        for line_no, line in find_pattern(content, r'ipv4_enabled\s*=\s*true'):
            hits.append(f'{format_location(f, line_no)}: {line}')

    if hits:
        detail = '; '.join(hits[:5])
        findings.append(make_finding(
            'gcp-network-002', SEVERITY_HIGH,
            'Cloud SQL with public IP (ipv4_enabled = true) in IaC',
            f'Cloud SQL public IP configurations: {detail}',
            f'grep -rn "ipv4_enabled" {IAC_ROOT}/',
            'Set ipv4_enabled = false in ip_configuration of google_sql_database_instance. '
            'Use Cloud SQL Auth Proxy or Private Service Connect for connectivity.',
        ))
    else:
        findings.append(finding_pass(
            'gcp-network-002', 'No Cloud SQL with public IP in IaC',
            f'grep -rn "ipv4_enabled" {IAC_ROOT}/',
        ))

    # Check 3: VPC subnets without log_config
    hits = []
    for f in tf_files:
        content = read_file(f)
        if re.search(r'resource\s+"google_compute_subnetwork"', content, re.IGNORECASE):
            if not re.search(r'log_config\s*\{', content, re.IGNORECASE):
                for line_no, line in find_pattern(content, r'resource\s+"google_compute_subnetwork"'):
                    hits.append(f'{format_location(f, line_no)}: Flow Logs not configured')

    if hits:
        detail = '; '.join(hits[:5])
        findings.append(make_finding(
            'gcp-network-003', SEVERITY_MEDIUM,
            'VPC subnet without Flow Logs in IaC',
            f'Subnets missing flow logs: {detail}',
            f'grep -rn "google_compute_subnetwork" {IAC_ROOT}/',
            'Add log_config block to google_compute_subnetwork: '
            'log_config { aggregation_interval = "INTERVAL_5_SEC" flow_sampling = 0.5 metadata = "INCLUDE_ALL_METADATA" }',
        ))
    else:
        findings.append(finding_pass(
            'gcp-network-003', 'All VPC subnets have Flow Logs in IaC',
            f'grep -rn "google_compute_subnetwork" {IAC_ROOT}/',
        ))

    return findings


# ---------------------------------------------------------------------------
# GCP Storage IaC checks
# ---------------------------------------------------------------------------

def check_gcp_storage_iac(tf_files):
    findings = []

    # Check 1: buckets without uniform_bucket_level_access = true
    hits = []
    for f in tf_files:
        content = read_file(f)
        if re.search(r'resource\s+"google_storage_bucket"', content, re.IGNORECASE):
            if not re.search(r'uniform_bucket_level_access\s*=\s*true', content, re.IGNORECASE):
                for line_no, line in find_pattern(content, r'resource\s+"google_storage_bucket"'):
                    hits.append(f'{format_location(f, line_no)}: uniform_bucket_level_access not set')

    if hits:
        detail = '; '.join(hits[:5])
        findings.append(make_finding(
            'gcp-storage-001', SEVERITY_HIGH,
            'Storage bucket without uniform bucket-level access in IaC',
            f'Buckets missing UBL access: {detail}',
            f'grep -rn "google_storage_bucket" {IAC_ROOT}/',
            'Set uniform_bucket_level_access = true in google_storage_bucket resource.',
        ))
    else:
        findings.append(finding_pass(
            'gcp-storage-001', 'All storage buckets have uniform access in IaC',
            f'grep -rn "google_storage_bucket" {IAC_ROOT}/',
        ))

    # Check 2: buckets without versioning enabled
    hits = []
    for f in tf_files:
        content = read_file(f)
        if re.search(r'resource\s+"google_storage_bucket"', content, re.IGNORECASE):
            if not re.search(r'versioning\s*\{[^}]*enabled\s*=\s*true', content, re.IGNORECASE | re.DOTALL):
                for line_no, line in find_pattern(content, r'resource\s+"google_storage_bucket"'):
                    hits.append(f'{format_location(f, line_no)}: versioning not enabled')

    if hits:
        detail = '; '.join(hits[:5])
        findings.append(make_finding(
            'gcp-storage-002', SEVERITY_MEDIUM,
            'Storage bucket without versioning in IaC',
            f'Buckets without versioning: {detail}',
            f'grep -rn "google_storage_bucket" {IAC_ROOT}/',
            'Add versioning block to google_storage_bucket: versioning { enabled = true }',
        ))
    else:
        findings.append(finding_pass(
            'gcp-storage-002', 'All storage buckets have versioning in IaC',
            f'grep -rn "google_storage_bucket" {IAC_ROOT}/',
        ))

    # Check 3: CMEK not configured
    hits = []
    for f in tf_files:
        content = read_file(f)
        if re.search(r'resource\s+"google_storage_bucket"', content, re.IGNORECASE):
            if not re.search(r'default_kms_key_name', content, re.IGNORECASE):
                for line_no, line in find_pattern(content, r'resource\s+"google_storage_bucket"'):
                    hits.append(f'{format_location(f, line_no)}: CMEK not configured')

    if hits:
        detail = '; '.join(hits[:5])
        findings.append(make_finding(
            'gcp-storage-003', SEVERITY_MEDIUM,
            'Storage bucket without CMEK in IaC',
            f'Buckets without CMEK: {detail}',
            f'grep -rn "default_kms_key_name" {IAC_ROOT}/',
            'Set default_kms_key_name in google_storage_bucket to use a customer-managed key.',
        ))
    else:
        findings.append(finding_pass(
            'gcp-storage-003', 'All storage buckets have CMEK in IaC',
            f'grep -rn "default_kms_key_name" {IAC_ROOT}/',
        ))

    return findings


# ---------------------------------------------------------------------------
# GCP Functions IaC checks
# ---------------------------------------------------------------------------

def check_gcp_functions_iac(tf_files):
    findings = []

    # Check 1: Cloud Functions v1 with allUsers in IAM
    hits = []
    for f in tf_files:
        content = read_file(f)
        if re.search(r'resource\s+"google_cloudfunctions_function_iam', content, re.IGNORECASE):
            for line_no, line in find_pattern(content, r'allUsers|allAuthenticatedUsers'):
                hits.append(f'{format_location(f, line_no)}: {line}')

    if hits:
        detail = '; '.join(hits[:5])
        findings.append(make_finding(
            'gcp-functions-001', SEVERITY_HIGH,
            'Cloud Function with public IAM binding in IaC',
            f'Public Cloud Function bindings: {detail}',
            f'grep -rn "allUsers" {IAC_ROOT}/',
            'Remove allUsers from google_cloudfunctions_function_iam_binding. '
            'Use authenticated callers via API Gateway or IAP.',
        ))
    else:
        findings.append(finding_pass(
            'gcp-functions-001', 'No public Cloud Function IAM bindings in IaC',
            f'grep -rn "allUsers" {IAC_ROOT}/',
        ))

    # Check 2: Cloud Run services with allow_unauthenticated = true
    hits = []
    for f in tf_files:
        content = read_file(f)
        for line_no, line in find_pattern(content, r'allow_unauthenticated\s*=\s*true'):
            hits.append(f'{format_location(f, line_no)}: {line}')

    if hits:
        detail = '; '.join(hits[:5])
        findings.append(make_finding(
            'gcp-functions-002', SEVERITY_HIGH,
            'Cloud Run service with allow_unauthenticated = true in IaC',
            f'Unauthenticated Cloud Run services: {detail}',
            f'grep -rn "allow_unauthenticated" {IAC_ROOT}/',
            'Set allow_unauthenticated = false in google_cloud_run_service and use '
            'IAP or Audience-aware ingress for authenticated access.',
        ))
    else:
        findings.append(finding_pass(
            'gcp-functions-002', 'No unauthenticated Cloud Run services in IaC',
            f'grep -rn "allow_unauthenticated" {IAC_ROOT}/',
        ))

    return findings


# ---------------------------------------------------------------------------
# GCP Databases IaC checks
# ---------------------------------------------------------------------------

def check_gcp_databases_iac(tf_files):
    findings = []

    # Check 1: Cloud SQL instances with public IP (ipv4_enabled = true or deletion_protection = false)
    hits = []
    for f in tf_files:
        content = read_file(f)
        if re.search(r'resource\s+"google_sql_database_instance"', content, re.IGNORECASE):
            for line_no, line in find_pattern(content, r'ipv4_enabled\s*=\s*true'):
                hits.append(f'{format_location(f, line_no)}: {line.strip()}')

    if hits:
        detail = '; '.join(hits[:5])
        findings.append(make_finding(
            'gcp-databases-001', SEVERITY_HIGH,
            'Cloud SQL instance with public IP in IaC',
            f'Instances with ipv4_enabled = true: {detail}',
            f'grep -rn "ipv4_enabled" {IAC_ROOT}/',
            'Set ipv4_enabled = false in google_sql_database_instance ip_configuration block '
            'and use Cloud SQL Auth Proxy or Private Service Connect instead.',
        ))
    else:
        findings.append(finding_pass(
            'gcp-databases-001', 'No Cloud SQL instances with public IP in IaC',
            f'grep -rn "ipv4_enabled" {IAC_ROOT}/',
        ))

    # Check 2: Cloud SQL instances without deletion protection
    hits = []
    for f in tf_files:
        content = read_file(f)
        if re.search(r'resource\s+"google_sql_database_instance"', content, re.IGNORECASE):
            if not re.search(r'deletion_protection\s*=\s*true', content, re.IGNORECASE):
                for line_no, line in find_pattern(content, r'resource\s+"google_sql_database_instance"'):
                    hits.append(f'{format_location(f, line_no)}: deletion_protection not set')

    if hits:
        detail = '; '.join(hits[:5])
        findings.append(make_finding(
            'gcp-databases-002', SEVERITY_MEDIUM,
            'Cloud SQL instance without deletion protection in IaC',
            f'Instances missing deletion protection: {detail}',
            f'grep -rn "google_sql_database_instance" {IAC_ROOT}/',
            'Set deletion_protection = true in google_sql_database_instance to prevent accidental deletion.',
        ))
    else:
        findings.append(finding_pass(
            'gcp-databases-002', 'All Cloud SQL instances have deletion_protection in IaC',
            f'grep -rn "google_sql_database_instance" {IAC_ROOT}/',
        ))

    # Check 3: Cloud SQL instances without backup configuration
    hits = []
    for f in tf_files:
        content = read_file(f)
        if re.search(r'resource\s+"google_sql_database_instance"', content, re.IGNORECASE):
            if not re.search(r'backup_configuration\s*\{[^}]*enabled\s*=\s*true', content, re.IGNORECASE | re.DOTALL):
                for line_no, line in find_pattern(content, r'resource\s+"google_sql_database_instance"'):
                    hits.append(f'{format_location(f, line_no)}: backup_configuration.enabled not set')

    if hits:
        detail = '; '.join(hits[:5])
        findings.append(make_finding(
            'gcp-databases-003', SEVERITY_MEDIUM,
            'Cloud SQL instance without backup enabled in IaC',
            f'Instances without backup configuration: {detail}',
            f'grep -rn "backup_configuration" {IAC_ROOT}/',
            'Add backup_configuration { enabled = true } to google_sql_database_instance settings block.',
        ))
    else:
        findings.append(finding_pass(
            'gcp-databases-003', 'All Cloud SQL instances have backup enabled in IaC',
            f'grep -rn "backup_configuration" {IAC_ROOT}/',
        ))

    # Check 4: Firestore/Spanner without CMEK key
    hits = []
    for f in tf_files:
        content = read_file(f)
        if re.search(r'resource\s+"google_spanner_instance"', content, re.IGNORECASE):
            if not re.search(r'encryption_config\s*\{', content, re.IGNORECASE):
                for line_no, line in find_pattern(content, r'resource\s+"google_spanner_instance"'):
                    hits.append(f'{format_location(f, line_no)}: encryption_config not set')

    if hits:
        detail = '; '.join(hits[:5])
        findings.append(make_finding(
            'gcp-databases-004', SEVERITY_MEDIUM,
            'Spanner instance without CMEK in IaC',
            f'Instances without encryption_config: {detail}',
            f'grep -rn "google_spanner_instance" {IAC_ROOT}/',
            'Add encryption_config { kms_key_name = var.kms_key } to google_spanner_instance.',
        ))
    else:
        findings.append(finding_pass(
            'gcp-databases-004', 'All Spanner instances have CMEK in IaC',
            f'grep -rn "google_spanner_instance" {IAC_ROOT}/',
        ))

    return findings


# ---------------------------------------------------------------------------
# GCP Analytics IaC checks
# ---------------------------------------------------------------------------

def check_gcp_analytics_iac(tf_files):
    findings = []

    # Check 1: BigQuery datasets with public IAM (allUsers/allAuthenticatedUsers)
    hits = []
    for f in tf_files:
        content = read_file(f)
        if re.search(r'resource\s+"google_bigquery_dataset_iam', content, re.IGNORECASE):
            for line_no, line in find_pattern(content, r'allUsers|allAuthenticatedUsers'):
                hits.append(f'{format_location(f, line_no)}: {line.strip()}')

    if hits:
        detail = '; '.join(hits[:5])
        findings.append(make_finding(
            'gcp-analytics-001', SEVERITY_CRITICAL,
            'BigQuery dataset with public IAM binding in IaC',
            f'Public BigQuery IAM bindings: {detail}',
            f'grep -rn "allUsers" {IAC_ROOT}/',
            'Remove allUsers/allAuthenticatedUsers from google_bigquery_dataset_iam_binding resources.',
        ))
    else:
        findings.append(finding_pass(
            'gcp-analytics-001', 'No public BigQuery IAM bindings in IaC',
            f'grep -rn "allUsers" {IAC_ROOT}/',
        ))

    # Check 2: BigQuery datasets without CMEK
    hits = []
    for f in tf_files:
        content = read_file(f)
        if re.search(r'resource\s+"google_bigquery_dataset"', content, re.IGNORECASE):
            if not re.search(r'default_encryption_configuration\s*\{', content, re.IGNORECASE):
                for line_no, line in find_pattern(content, r'resource\s+"google_bigquery_dataset"'):
                    hits.append(f'{format_location(f, line_no)}: default_encryption_configuration not set')

    if hits:
        detail = '; '.join(hits[:5])
        findings.append(make_finding(
            'gcp-analytics-002', SEVERITY_MEDIUM,
            'BigQuery dataset without CMEK in IaC',
            f'Datasets without default encryption: {detail}',
            f'grep -rn "google_bigquery_dataset" {IAC_ROOT}/',
            'Add default_encryption_configuration { kms_key_name = var.kms_key } to google_bigquery_dataset.',
        ))
    else:
        findings.append(finding_pass(
            'gcp-analytics-002', 'All BigQuery datasets have CMEK in IaC',
            f'grep -rn "google_bigquery_dataset" {IAC_ROOT}/',
        ))

    # Check 3: Pub/Sub topics without CMEK
    hits = []
    for f in tf_files:
        content = read_file(f)
        if re.search(r'resource\s+"google_pubsub_topic"', content, re.IGNORECASE):
            if not re.search(r'kms_key_name', content, re.IGNORECASE):
                for line_no, line in find_pattern(content, r'resource\s+"google_pubsub_topic"'):
                    hits.append(f'{format_location(f, line_no)}: kms_key_name not set')

    if hits:
        detail = '; '.join(hits[:5])
        findings.append(make_finding(
            'gcp-analytics-003', SEVERITY_MEDIUM,
            'Pub/Sub topic without CMEK in IaC',
            f'Topics without kms_key_name: {detail}',
            f'grep -rn "google_pubsub_topic" {IAC_ROOT}/',
            'Add kms_key_name = var.kms_key to google_pubsub_topic resources.',
        ))
    else:
        findings.append(finding_pass(
            'gcp-analytics-003', 'All Pub/Sub topics have CMEK in IaC',
            f'grep -rn "google_pubsub_topic" {IAC_ROOT}/',
        ))

    # Check 4: BigQuery dataset without delete_contents_on_destroy protection
    hits = []
    for f in tf_files:
        content = read_file(f)
        if re.search(r'resource\s+"google_bigquery_dataset"', content, re.IGNORECASE):
            if re.search(r'delete_contents_on_destroy\s*=\s*true', content, re.IGNORECASE):
                for line_no, line in find_pattern(content, r'delete_contents_on_destroy\s*=\s*true'):
                    hits.append(f'{format_location(f, line_no)}: {line.strip()}')

    if hits:
        detail = '; '.join(hits[:5])
        findings.append(make_finding(
            'gcp-analytics-004', SEVERITY_HIGH,
            'BigQuery dataset with delete_contents_on_destroy = true in IaC',
            f'Datasets with destructive delete enabled: {detail}',
            f'grep -rn "delete_contents_on_destroy" {IAC_ROOT}/',
            'Remove or set delete_contents_on_destroy = false in google_bigquery_dataset to prevent accidental data loss.',
        ))
    else:
        findings.append(finding_pass(
            'gcp-analytics-004', 'No BigQuery datasets with delete_contents_on_destroy in IaC',
            f'grep -rn "delete_contents_on_destroy" {IAC_ROOT}/',
        ))

    return findings


# ---------------------------------------------------------------------------
# Subsystem dispatcher — keyed by (platform, subsystem) so future platforms
# (e.g. aws) can register their own check functions here.
# ---------------------------------------------------------------------------

PLATFORM_SUBSYSTEM_CHECKS = {
    'gcp': {
        'iam': check_gcp_iam_iac,
        'compute': check_gcp_compute_iac,
        'network': check_gcp_network_iac,
        'storage': check_gcp_storage_iac,
        'functions': check_gcp_functions_iac,
        'databases': check_gcp_databases_iac,
        'analytics': check_gcp_analytics_iac,
    },
}


def run_subsystem(platform, subsystem, tf_files, audit_id, audit_dir, timestamp):
    check_fn = PLATFORM_SUBSYSTEM_CHECKS.get(platform, {}).get(subsystem)
    if check_fn is None:
        print(f'  [SKIP] No {platform}/{subsystem} checks implemented', file=sys.stderr)
        return None

    print(f'  Reviewing {platform}/{subsystem}...', flush=True)
    findings = check_fn(tf_files)

    result = {
        'audit_id': audit_id,
        'platform': platform,
        'subsystem': subsystem,
        'timestamp': timestamp,
        'findings': findings,
    }

    output_path = audit_dir / f'{platform}-{subsystem}.json'
    with open(output_path, 'w') as f:
        json.dump(result, f, indent=2)

    return findings


# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------

def print_summary(audit_id, all_results):
    total_fail = sum(
        sum(1 for f in findings if f['status'] == 'fail')
        for findings in all_results.values()
    )
    total_pass = sum(
        sum(1 for f in findings if f['status'] == 'pass')
        for findings in all_results.values()
    )

    print()
    print(f'Audit ID : {audit_id}')
    print(f'{"Subsystem":<18} {"PASS":>5} {"FAIL":>5}')
    print('-' * 32)
    for subsystem, findings in all_results.items():
        passes = sum(1 for f in findings if f['status'] == 'pass')
        fails = sum(1 for f in findings if f['status'] == 'fail')
        print(f'{subsystem:<18} {passes:>5} {fails:>5}')
    print('-' * 32)
    print(f'{"TOTAL":<18} {total_pass:>5} {total_fail:>5}')

    if total_fail > 0:
        print(f'\n{total_fail} finding(s) require attention. Run: /sectool refactor {audit_id}')
    else:
        print('\nAll checks passed.')


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main():
    args = parse_args()

    # Validate platforms
    invalid_platforms = [p for p in args.platforms if p not in SUPPORTED_PLATFORMS]
    if invalid_platforms:
        print(f'ERROR: Unsupported platform(s): {invalid_platforms}', file=sys.stderr)
        print(f'       Supported: {SUPPORTED_PLATFORMS}', file=sys.stderr)
        sys.exit(1)

    # Validate subsystems
    invalid_subsystems = [s for s in args.subsystems if s not in SUPPORTED_SUBSYSTEMS]
    if invalid_subsystems:
        print(f'ERROR: Unsupported subsystem(s): {invalid_subsystems}', file=sys.stderr)
        print(f'       Supported: {SUPPORTED_SUBSYSTEMS}', file=sys.stderr)
        sys.exit(1)

    if args.check_args:
        print(json.dumps(vars(args)))
        return

    # Generate audit_id
    timestamp_str = datetime.now(timezone.utc).strftime('%Y%m%d-%H%M%S')
    audit_id = args.audit_id or f'{timestamp_str}-review'
    iso_timestamp = datetime.now(timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ')

    # Collect IaC files
    tf_files = collect_tf_files()
    if not tf_files:
        print(f'WARNING: No .tf files found under {IAC_ROOT}/. Nothing to review.', file=sys.stderr)

    # Resolve .audits directory relative to CWD
    audits_root = Path('.audits')
    audit_dir = audits_root / audit_id
    audit_dir.mkdir(parents=True, exist_ok=True)

    print(f'Review ID        : {audit_id}')
    print(f'IaC root         : {IAC_ROOT}')
    print(f'Files found      : {len(tf_files)} .tf file(s)')
    print(f'Output directory : {audit_dir}')
    print(f'Platforms        : {args.platforms}')
    print(f'Subsystems       : {args.subsystems}')
    print()

    all_results = {}

    for platform in args.platforms:
        for subsystem in args.subsystems:
            findings = run_subsystem(platform, subsystem, tf_files, audit_id, audit_dir, iso_timestamp)
            if findings is not None:
                all_results[f'{platform}/{subsystem}'] = findings

    print_summary(audit_id, all_results)


if __name__ == '__main__':
    main()
