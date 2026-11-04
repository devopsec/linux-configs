#!/usr/bin/env python3
"""
audit.py — Live GCP security scanner.

Scans live GCP resources for security misconfigurations and writes structured
findings to .audits/<audit_id>/gcp-<subsystem>.json.

Usage:
    audit.py [-p <platform> ...] [-s <subsystem> ...] [-i <audit_id>]
"""

import argparse
import json
import os
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path


SUPPORTED_PLATFORMS = ['gcp']
SUPPORTED_SUBSYSTEMS = ['iam', 'compute', 'network', 'storage', 'functions', 'databases', 'analytics']

SEVERITY_CRITICAL = 'CRITICAL'
SEVERITY_HIGH = 'HIGH'
SEVERITY_MEDIUM = 'MEDIUM'
SEVERITY_INFO = 'INFO'


# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------

def parse_args():
    parser = argparse.ArgumentParser(
        prog='sectool audit',
        description='Audit live GCP resources for security misconfigurations',
        add_help=True,
    )
    parser.add_argument(
        '-p', dest='platforms', metavar='platform', nargs='+',
        default=SUPPORTED_PLATFORMS,
        help=f'Platform(s) to audit (default: all — {SUPPORTED_PLATFORMS})',
    )
    parser.add_argument(
        '-s', dest='subsystems', metavar='subsystem', nargs='+',
        default=SUPPORTED_SUBSYSTEMS,
        help=f'Subsystem(s) to audit (default: all — {SUPPORTED_SUBSYSTEMS})',
    )
    parser.add_argument(
        '-i', dest='audit_id', metavar='audit_id', default=None,
        help='Override the generated audit_id (form: YYYYMMDD-HHMMSS-audit)',
    )
    parser.add_argument(
        '--check-args', action='store_true',
        help='parse arguments, print them as JSON and exit (no GCP access)',
    )
    return parser.parse_args()


# ---------------------------------------------------------------------------
# Pre-flight
# ---------------------------------------------------------------------------

def check_gcloud_auth():
    """Exit with a clear error if gcloud is not authenticated."""
    result = subprocess.run(
        ['gcloud', 'auth', 'list', '--filter=status:ACTIVE', '--format=value(account)'],
        capture_output=True, text=True,
    )
    if result.returncode != 0 or not result.stdout.strip():
        print('ERROR: No active gcloud authentication found.', file=sys.stderr)
        print('       Run: gcloud auth login', file=sys.stderr)
        sys.exit(1)
    return result.stdout.strip().splitlines()[0]


def get_active_project():
    """Return the currently configured gcloud project ID."""
    result = subprocess.run(
        ['gcloud', 'config', 'get-value', 'project'],
        capture_output=True, text=True,
    )
    project = result.stdout.strip()
    if not project or project == '(unset)':
        print('ERROR: No gcloud project configured.', file=sys.stderr)
        print('       Run: gcloud config set project PROJECT_ID', file=sys.stderr)
        sys.exit(1)
    return project


def run_cmd(cmd):
    """Run a shell command and return (stdout, stderr, returncode)."""
    result = subprocess.run(cmd, capture_output=True, text=True, shell=isinstance(cmd, str))
    return result.stdout.strip(), result.stderr.strip(), result.returncode


# ---------------------------------------------------------------------------
# Finding helpers
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
# GCP IAM checks
# ---------------------------------------------------------------------------

def check_gcp_iam(project_id):
    findings = []

    # Check 1: primitive role bindings
    cmd = (
        f'gcloud asset search-all-iam-policies --scope=projects/{project_id} '
        f'--query="policy:roles/editor OR policy:roles/owner OR policy:roles/viewer" '
        f'--format=json'
    )
    stdout, _, rc = run_cmd(cmd)
    check_cmd_str = cmd
    if rc == 0 and stdout and stdout != '[]':
        try:
            results = json.loads(stdout)
        except json.JSONDecodeError:
            results = []
        if results:
            details = ', '.join(r.get('resource', '') for r in results[:5])
            findings.append(make_finding(
                'gcp-iam-001', SEVERITY_CRITICAL,
                'Primitive role binding detected',
                f'Primitive roles (owner/editor/viewer) found on: {details}',
                check_cmd_str,
                'Replace primitive roles with predefined roles scoped to specific resources. '
                'See: gcloud projects get-iam-policy PROJECT_ID for full binding list.',
            ))
        else:
            findings.append(finding_pass('gcp-iam-001', 'No primitive role bindings', check_cmd_str))
    else:
        findings.append(finding_pass('gcp-iam-001', 'No primitive role bindings', check_cmd_str))

    # Check 2: allUsers bindings
    cmd = (
        f'gcloud asset search-all-iam-policies --scope=projects/{project_id} '
        f'--query="policy:allUsers" --format=json'
    )
    stdout, _, rc = run_cmd(cmd)
    check_cmd_str = cmd
    if rc == 0 and stdout and stdout != '[]':
        try:
            results = json.loads(stdout)
        except json.JSONDecodeError:
            results = []
        if results:
            details = ', '.join(r.get('resource', '') for r in results[:5])
            findings.append(make_finding(
                'gcp-iam-002', SEVERITY_CRITICAL,
                'Public allUsers IAM binding detected',
                f'allUsers binding found on: {details}',
                check_cmd_str,
                'Remove allUsers bindings immediately. Use authenticated identities and '
                'API Gateway or load balancer for public-facing endpoints.',
            ))
        else:
            findings.append(finding_pass('gcp-iam-002', 'No allUsers bindings', check_cmd_str))
    else:
        findings.append(finding_pass('gcp-iam-002', 'No allUsers bindings', check_cmd_str))

    # Check 3: allAuthenticatedUsers bindings
    cmd = (
        f'gcloud asset search-all-iam-policies --scope=projects/{project_id} '
        f'--query="policy:allAuthenticatedUsers" --format=json'
    )
    stdout, _, rc = run_cmd(cmd)
    check_cmd_str = cmd
    if rc == 0 and stdout and stdout != '[]':
        try:
            results = json.loads(stdout)
        except json.JSONDecodeError:
            results = []
        if results:
            details = ', '.join(r.get('resource', '') for r in results[:5])
            findings.append(make_finding(
                'gcp-iam-003', SEVERITY_HIGH,
                'allAuthenticatedUsers IAM binding detected',
                f'allAuthenticatedUsers binding found on: {details}',
                check_cmd_str,
                'Remove allAuthenticatedUsers bindings. This grants access to any Google '
                'account worldwide. Use specific service accounts or user groups instead.',
            ))
        else:
            findings.append(finding_pass('gcp-iam-003', 'No allAuthenticatedUsers bindings', check_cmd_str))
    else:
        findings.append(finding_pass('gcp-iam-003', 'No allAuthenticatedUsers bindings', check_cmd_str))

    # Check 4: default compute service account usage on instances
    cmd = (
        f'gcloud compute instances list --project={project_id} '
        f'--format=json '
        f'--filter="serviceAccounts.email~\'compute@developer.gserviceaccount.com\'"'
    )
    stdout, _, rc = run_cmd(cmd)
    check_cmd_str = cmd
    if rc == 0 and stdout and stdout != '[]':
        try:
            results = json.loads(stdout)
        except json.JSONDecodeError:
            results = []
        if results:
            names = ', '.join(r.get('name', '') for r in results[:5])
            findings.append(make_finding(
                'gcp-iam-004', SEVERITY_HIGH,
                'Default compute service account in use',
                f'Instances using default compute SA: {names}',
                check_cmd_str,
                'Create dedicated service accounts per workload with minimal permissions. '
                'The default compute SA has Editor on the project.',
            ))
        else:
            findings.append(finding_pass('gcp-iam-004', 'No instances using default compute SA', check_cmd_str))
    else:
        findings.append(finding_pass('gcp-iam-004', 'No instances using default compute SA', check_cmd_str))

    return findings


# ---------------------------------------------------------------------------
# GCP Compute checks
# ---------------------------------------------------------------------------

def check_gcp_compute(project_id):
    findings = []

    # Check 1: instances with public IPs
    cmd = (
        f'gcloud compute instances list --project={project_id} '
        f'--format=json --filter="networkInterfaces[].accessConfigs[].natIP:*"'
    )
    stdout, _, rc = run_cmd(cmd)
    check_cmd_str = cmd
    if rc == 0 and stdout and stdout != '[]':
        try:
            results = json.loads(stdout)
        except json.JSONDecodeError:
            results = []
        if results:
            names = ', '.join(r.get('name', '') for r in results[:5])
            findings.append(make_finding(
                'gcp-compute-001', SEVERITY_HIGH,
                'Compute instances with public IP addresses',
                f'Instances with public IPs: {names}',
                check_cmd_str,
                'Remove public IPs from compute instances. Use Cloud NAT for outbound '
                'access and IAP or load balancers for inbound.',
            ))
        else:
            findings.append(finding_pass('gcp-compute-001', 'No instances with public IPs', check_cmd_str))
    else:
        findings.append(finding_pass('gcp-compute-001', 'No instances with public IPs', check_cmd_str))

    # Check 2: instances without OS Login
    cmd = (
        f'gcloud compute instances list --project={project_id} '
        f'--format=json --filter="metadata.items[key=enable-oslogin].value!=TRUE"'
    )
    stdout, _, rc = run_cmd(cmd)
    check_cmd_str = cmd
    if rc == 0 and stdout and stdout != '[]':
        try:
            results = json.loads(stdout)
        except json.JSONDecodeError:
            results = []
        if results:
            names = ', '.join(r.get('name', '') for r in results[:5])
            findings.append(make_finding(
                'gcp-compute-002', SEVERITY_MEDIUM,
                'Instances without OS Login enabled',
                f'Instances without OS Login: {names}',
                check_cmd_str,
                'Enable OS Login on all instances: '
                'gcloud compute instances add-metadata INSTANCE --metadata=enable-oslogin=TRUE',
            ))
        else:
            findings.append(finding_pass('gcp-compute-002', 'All instances have OS Login enabled', check_cmd_str))
    else:
        findings.append(finding_pass('gcp-compute-002', 'All instances have OS Login enabled', check_cmd_str))

    return findings


# ---------------------------------------------------------------------------
# GCP Network checks
# ---------------------------------------------------------------------------

def check_gcp_network(project_id):
    findings = []

    # Check 1: SSH (22) open to the world
    cmd = (
        f'gcloud compute firewall-rules list --project={project_id} '
        f'--filter="sourceRanges:0.0.0.0/0 AND allowed[].ports:22" '
        f'--format=json'
    )
    stdout, _, rc = run_cmd(cmd)
    check_cmd_str = cmd
    if rc == 0 and stdout and stdout != '[]':
        try:
            results = json.loads(stdout)
        except json.JSONDecodeError:
            results = []
        if results:
            names = ', '.join(r.get('name', '') for r in results)
            findings.append(make_finding(
                'gcp-network-001', SEVERITY_CRITICAL,
                'SSH port 22 open to 0.0.0.0/0',
                f'Firewall rules allowing SSH from anywhere: {names}',
                check_cmd_str,
                'Restrict SSH to IAP only: source-ranges=35.235.240.0/20. '
                'Delete world-open SSH rules and create: '
                'gcloud compute firewall-rules create allow-iap-ssh --source-ranges=35.235.240.0/20 --rules=tcp:22',
            ))
        else:
            findings.append(finding_pass('gcp-network-001', 'No SSH rules open to 0.0.0.0/0', check_cmd_str))
    else:
        findings.append(finding_pass('gcp-network-001', 'No SSH rules open to 0.0.0.0/0', check_cmd_str))

    # Check 2: any protocol open to the world (all)
    cmd = (
        f'gcloud compute firewall-rules list --project={project_id} '
        f'--filter="sourceRanges:0.0.0.0/0 AND allowed[].IPProtocol:all" '
        f'--format=json'
    )
    stdout, _, rc = run_cmd(cmd)
    check_cmd_str = cmd
    if rc == 0 and stdout and stdout != '[]':
        try:
            results = json.loads(stdout)
        except json.JSONDecodeError:
            results = []
        if results:
            names = ', '.join(r.get('name', '') for r in results)
            findings.append(make_finding(
                'gcp-network-002', SEVERITY_CRITICAL,
                'All-protocols firewall rule open to 0.0.0.0/0',
                f'Firewall rules allowing all traffic from anywhere: {names}',
                check_cmd_str,
                'Delete or restrict these firewall rules immediately. '
                'Use explicit allow rules for specific ports and services only.',
            ))
        else:
            findings.append(finding_pass('gcp-network-002', 'No all-protocols rules open to 0.0.0.0/0', check_cmd_str))
    else:
        findings.append(finding_pass('gcp-network-002', 'No all-protocols rules open to 0.0.0.0/0', check_cmd_str))

    # Check 3: Cloud SQL with public IP
    cmd = (
        f'gcloud sql instances list --project={project_id} '
        f'--filter="settings.ipConfiguration.ipv4Enabled=true" '
        f'--format=json'
    )
    stdout, _, rc = run_cmd(cmd)
    check_cmd_str = cmd
    if rc == 0 and stdout and stdout != '[]':
        try:
            results = json.loads(stdout)
        except json.JSONDecodeError:
            results = []
        if results:
            names = ', '.join(r.get('name', '') for r in results)
            findings.append(make_finding(
                'gcp-network-003', SEVERITY_HIGH,
                'Cloud SQL instance with public IP enabled',
                f'Cloud SQL instances with public IP: {names}',
                check_cmd_str,
                'Disable public IP on Cloud SQL and use Cloud SQL Auth Proxy or Private Service Connect. '
                'gcloud sql instances patch INSTANCE --no-assign-ip',
            ))
        else:
            findings.append(finding_pass('gcp-network-003', 'No Cloud SQL instances with public IP', check_cmd_str))
    else:
        findings.append(finding_pass('gcp-network-003', 'No Cloud SQL instances with public IP', check_cmd_str))

    # Check 4: VPC Flow Logs disabled
    cmd = (
        f'gcloud compute networks subnets list --project={project_id} '
        f'--filter="logConfig.enable!=true" --format=json'
    )
    stdout, _, rc = run_cmd(cmd)
    check_cmd_str = cmd
    if rc == 0 and stdout and stdout != '[]':
        try:
            results = json.loads(stdout)
        except json.JSONDecodeError:
            results = []
        if results:
            names = ', '.join(r.get('name', '') for r in results[:5])
            findings.append(make_finding(
                'gcp-network-004', SEVERITY_MEDIUM,
                'VPC subnets without Flow Logs enabled',
                f'Subnets without Flow Logs: {names}',
                check_cmd_str,
                'Enable VPC Flow Logs on all subnets: '
                'gcloud compute networks subnets update SUBNET --region=REGION --enable-flow-logs',
            ))
        else:
            findings.append(finding_pass('gcp-network-004', 'All subnets have Flow Logs enabled', check_cmd_str))
    else:
        findings.append(finding_pass('gcp-network-004', 'All subnets have Flow Logs enabled', check_cmd_str))

    return findings


# ---------------------------------------------------------------------------
# GCP Storage checks
# ---------------------------------------------------------------------------

def check_gcp_storage(project_id):
    findings = []

    # Check 1: public buckets (allUsers)
    cmd = f'gcloud asset search-all-iam-policies --scope=projects/{project_id} --query="policy:allUsers" --format=json'
    stdout, _, rc = run_cmd(cmd)
    check_cmd_str = cmd
    if rc == 0 and stdout and stdout != '[]':
        try:
            results = json.loads(stdout)
        except json.JSONDecodeError:
            results = []
        storage_results = [r for r in results if 'storage.googleapis.com' in r.get('resource', '')]
        if storage_results:
            names = ', '.join(r.get('resource', '') for r in storage_results[:5])
            findings.append(make_finding(
                'gcp-storage-001', SEVERITY_CRITICAL,
                'Public Cloud Storage bucket (allUsers)',
                f'Buckets with allUsers binding: {names}',
                check_cmd_str,
                'Remove allUsers IAM binding from buckets. Enable uniform bucket-level access and '
                'public access prevention: gcloud storage buckets update gs://BUCKET --no-public-access',
            ))
        else:
            findings.append(finding_pass('gcp-storage-001', 'No public storage buckets', check_cmd_str))
    else:
        findings.append(finding_pass('gcp-storage-001', 'No public storage buckets', check_cmd_str))

    # Check 2: buckets without uniform access
    cmd = f'gcloud storage buckets list --project={project_id} --format=json'
    stdout, _, rc = run_cmd(cmd)
    check_cmd_str = cmd
    if rc == 0 and stdout and stdout != '[]':
        try:
            results = json.loads(stdout)
        except json.JSONDecodeError:
            results = []
        non_uniform = [
            r for r in results
            if not r.get('iamConfiguration', {}).get('uniformBucketLevelAccess', {}).get('enabled', False)
        ]
        if non_uniform:
            names = ', '.join(r.get('name', '') for r in non_uniform[:5])
            findings.append(make_finding(
                'gcp-storage-002', SEVERITY_HIGH,
                'Buckets without uniform bucket-level access',
                f'Buckets without UBL access: {names}',
                check_cmd_str,
                'Enable uniform bucket-level access: '
                'gcloud storage buckets update gs://BUCKET --uniform-bucket-level-access',
            ))
        else:
            findings.append(finding_pass('gcp-storage-002', 'All buckets have uniform access enabled', check_cmd_str))
    else:
        findings.append(finding_pass('gcp-storage-002', 'All buckets have uniform access enabled', check_cmd_str))

    return findings


# ---------------------------------------------------------------------------
# GCP Functions checks
# ---------------------------------------------------------------------------

def check_gcp_functions(project_id):
    findings = []

    # Check 1: Cloud Functions with allUsers invoker
    cmd = f'gcloud functions list --project={project_id} --format=value(name)'
    stdout, _, rc = run_cmd(cmd)
    check_cmd_str = f'gcloud functions list --project={project_id} + get-iam-policy per function'

    public_fns = []
    if rc == 0 and stdout:
        for fn in stdout.splitlines():
            fn = fn.strip()
            if not fn:
                continue
            policy_stdout, _, policy_rc = run_cmd(
                ['gcloud', 'functions', 'get-iam-policy', fn, '--project', project_id, '--format=json']
            )
            if policy_rc == 0 and 'allUsers' in policy_stdout:
                public_fns.append(fn)

    if public_fns:
        findings.append(make_finding(
            'gcp-functions-001', SEVERITY_HIGH,
            'Cloud Functions with allUsers invoker binding',
            f'Publicly invocable functions: {", ".join(public_fns)}',
            check_cmd_str,
            'Remove allUsers invoker binding from Cloud Functions. '
            'Use API Gateway or Cloud Load Balancing with authentication instead.',
        ))
    else:
        findings.append(finding_pass('gcp-functions-001', 'No publicly accessible Cloud Functions', check_cmd_str))

    # Check 2: Cloud Run services with allUsers invoker
    cmd = f'gcloud run services list --project={project_id} --format=value(metadata.name)'
    stdout, _, rc = run_cmd(cmd)
    check_cmd_str = f'gcloud run services list --project={project_id} + get-iam-policy per service'

    public_svcs = []
    if rc == 0 and stdout:
        for svc in stdout.splitlines():
            svc = svc.strip()
            if not svc:
                continue
            # Cloud Run requires a region; try listing with all regions
            policy_stdout, _, policy_rc = run_cmd(
                ['gcloud', 'run', 'services', 'get-iam-policy', svc,
                 '--project', project_id, '--format=json', '--region=-']
            )
            if policy_rc == 0 and 'allUsers' in policy_stdout:
                public_svcs.append(svc)

    if public_svcs:
        findings.append(make_finding(
            'gcp-functions-002', SEVERITY_HIGH,
            'Cloud Run services with allUsers invoker binding',
            f'Publicly invocable Cloud Run services: {", ".join(public_svcs)}',
            check_cmd_str,
            'Remove allUsers invoker binding from Cloud Run services. '
            'Use load balancer with IAP or Identity-Aware Proxy for access control.',
        ))
    else:
        findings.append(finding_pass('gcp-functions-002', 'No publicly accessible Cloud Run services', check_cmd_str))

    return findings


# ---------------------------------------------------------------------------
# GCP Databases checks
# ---------------------------------------------------------------------------

def check_gcp_databases(project_id):
    findings = []

    # Check 1: Cloud SQL instances with public IP enabled
    cmd = f'gcloud sql instances list --project={project_id} --format=json'
    stdout, _, rc = run_cmd(cmd)
    check_cmd_str = cmd
    if rc == 0 and stdout and stdout != '[]':
        try:
            instances = json.loads(stdout)
        except json.JSONDecodeError:
            instances = []
        public_ip_instances = [
            inst.get('name', '') for inst in instances
            if inst.get('settings', {}).get('ipConfiguration', {}).get('ipv4Enabled', False)
        ]
        if public_ip_instances:
            findings.append(make_finding(
                'gcp-databases-001', SEVERITY_HIGH,
                'Cloud SQL instance with public IP enabled',
                f'Instances with public IP: {", ".join(public_ip_instances)}',
                check_cmd_str,
                'Disable public IP on Cloud SQL instances and use Cloud SQL Auth Proxy or Private Service Connect: '
                'gcloud sql instances patch INSTANCE --no-assign-ip',
            ))
        else:
            findings.append(finding_pass('gcp-databases-001', 'No Cloud SQL instances with public IP', check_cmd_str))
    else:
        findings.append(finding_pass('gcp-databases-001', 'No Cloud SQL instances found or listing failed', check_cmd_str))

    # Check 2: Cloud SQL instances without automated backups
    if rc == 0 and stdout and stdout != '[]':
        try:
            instances = json.loads(stdout)
        except json.JSONDecodeError:
            instances = []
        no_backup = [
            inst.get('name', '') for inst in instances
            if not inst.get('settings', {}).get('backupConfiguration', {}).get('enabled', False)
        ]
        if no_backup:
            findings.append(make_finding(
                'gcp-databases-002', SEVERITY_MEDIUM,
                'Cloud SQL instance without automated backups',
                f'Instances without backups: {", ".join(no_backup)}',
                check_cmd_str,
                'Enable automated backups on Cloud SQL instances: '
                'gcloud sql instances patch INSTANCE --backup-start-time=02:00',
            ))
        else:
            findings.append(finding_pass('gcp-databases-002', 'All Cloud SQL instances have automated backups', check_cmd_str))

    # Check 3: Cloud SQL instances without SSL enforcement
    if rc == 0 and stdout and stdout != '[]':
        try:
            instances = json.loads(stdout)
        except json.JSONDecodeError:
            instances = []
        no_ssl = [
            inst.get('name', '') for inst in instances
            if inst.get('settings', {}).get('ipConfiguration', {}).get('requireSsl', True) is False
        ]
        if no_ssl:
            findings.append(make_finding(
                'gcp-databases-003', SEVERITY_HIGH,
                'Cloud SQL instance with SSL not enforced',
                f'Instances without SSL enforcement: {", ".join(no_ssl)}',
                check_cmd_str,
                'Enforce SSL on Cloud SQL instances: '
                'gcloud sql instances patch INSTANCE --require-ssl',
            ))
        else:
            findings.append(finding_pass('gcp-databases-003', 'All Cloud SQL instances enforce SSL', check_cmd_str))

    # Check 4: Firestore/Datastore — check for overly permissive IAM on database resources
    cmd2 = (f'gcloud asset search-all-iam-policies --scope=projects/{project_id} '
            f'--query="policy:allUsers" --format=json')
    stdout2, _, rc2 = run_cmd(cmd2)
    check_cmd_str2 = cmd2
    if rc2 == 0 and stdout2 and stdout2 != '[]':
        try:
            results = json.loads(stdout2)
        except json.JSONDecodeError:
            results = []
        db_results = [
            r for r in results
            if any(svc in r.get('resource', '') for svc in ['firestore', 'datastore', 'spanner', 'bigtable'])
        ]
        if db_results:
            names = ', '.join(r.get('resource', '') for r in db_results[:5])
            findings.append(make_finding(
                'gcp-databases-004', SEVERITY_CRITICAL,
                'Database resource with allUsers IAM binding',
                f'Public database resources: {names}',
                check_cmd_str2,
                'Remove allUsers IAM bindings from Firestore/Spanner/Bigtable resources immediately.',
            ))
        else:
            findings.append(finding_pass('gcp-databases-004', 'No public IAM bindings on database resources', check_cmd_str2))
    else:
        findings.append(finding_pass('gcp-databases-004', 'No public IAM bindings on database resources', check_cmd_str2))

    return findings


# ---------------------------------------------------------------------------
# GCP Analytics checks
# ---------------------------------------------------------------------------

def check_gcp_analytics(project_id):
    findings = []

    # Check 1: BigQuery datasets with public access (allUsers/allAuthenticatedUsers)
    cmd = f'gcloud asset search-all-iam-policies --scope=projects/{project_id} --query="policy:allUsers OR policy:allAuthenticatedUsers" --format=json'
    stdout, _, rc = run_cmd(cmd)
    check_cmd_str = cmd
    if rc == 0 and stdout and stdout != '[]':
        try:
            results = json.loads(stdout)
        except json.JSONDecodeError:
            results = []
        bq_results = [r for r in results if 'bigquery' in r.get('resource', '')]
        if bq_results:
            names = ', '.join(r.get('resource', '') for r in bq_results[:5])
            findings.append(make_finding(
                'gcp-analytics-001', SEVERITY_CRITICAL,
                'BigQuery dataset with public IAM binding',
                f'Public BigQuery resources: {names}',
                check_cmd_str,
                'Remove allUsers/allAuthenticatedUsers IAM bindings from BigQuery datasets: '
                'gcloud projects get-iam-policy PROJECT and remove public members from bigquery.dataViewer bindings.',
            ))
        else:
            findings.append(finding_pass('gcp-analytics-001', 'No public BigQuery IAM bindings', check_cmd_str))
    else:
        findings.append(finding_pass('gcp-analytics-001', 'No public BigQuery IAM bindings', check_cmd_str))

    # Check 2: BigQuery datasets without CMEK
    cmd2 = f'gcloud bigquery datasets list --project={project_id} --format=json'
    stdout2, _, rc2 = run_cmd(cmd2)
    check_cmd_str2 = cmd2
    if rc2 == 0 and stdout2 and stdout2 != '[]':
        try:
            datasets = json.loads(stdout2)
        except json.JSONDecodeError:
            datasets = []
        no_cmek = []
        for ds in datasets:
            ds_id = ds.get('datasetReference', {}).get('datasetId', '')
            detail_stdout, _, detail_rc = run_cmd(
                ['gcloud', 'bigquery', 'datasets', 'describe', ds_id,
                 '--project', project_id, '--format=json']
            )
            if detail_rc == 0:
                try:
                    detail = json.loads(detail_stdout)
                except json.JSONDecodeError:
                    detail = {}
                if not detail.get('defaultEncryptionConfiguration', {}).get('kmsKeyName'):
                    no_cmek.append(ds_id)
        if no_cmek:
            findings.append(make_finding(
                'gcp-analytics-002', SEVERITY_MEDIUM,
                'BigQuery dataset without CMEK',
                f'Datasets without customer-managed encryption: {", ".join(no_cmek[:5])}',
                check_cmd_str2,
                'Configure CMEK on BigQuery datasets: set defaultEncryptionConfiguration.kmsKeyName '
                'in the dataset resource or use gcloud bigquery datasets update --default-kms-key=KEY_NAME.',
            ))
        else:
            findings.append(finding_pass('gcp-analytics-002', 'All BigQuery datasets have CMEK configured', check_cmd_str2))
    else:
        findings.append(finding_pass('gcp-analytics-002', 'No BigQuery datasets found or listing failed', check_cmd_str2))

    # Check 3: Dataflow jobs using default service account
    cmd3 = f'gcloud dataflow jobs list --project={project_id} --format=json'
    stdout3, _, rc3 = run_cmd(cmd3)
    check_cmd_str3 = cmd3
    if rc3 == 0 and stdout3 and stdout3 != '[]':
        try:
            jobs = json.loads(stdout3)
        except json.JSONDecodeError:
            jobs = []
        default_sa_jobs = [
            j.get('name', j.get('id', '')) for j in jobs
            if 'compute@developer.gserviceaccount.com' in j.get('environment', {}).get('serviceAccountEmail', '')
        ]
        if default_sa_jobs:
            findings.append(make_finding(
                'gcp-analytics-003', SEVERITY_MEDIUM,
                'Dataflow job using default Compute service account',
                f'Jobs with default SA: {", ".join(default_sa_jobs[:5])}',
                check_cmd_str3,
                'Create a dedicated service account with minimal permissions for Dataflow jobs '
                'and specify it with --service-account-email when launching jobs.',
            ))
        else:
            findings.append(finding_pass('gcp-analytics-003', 'No Dataflow jobs using default service account', check_cmd_str3))
    else:
        findings.append(finding_pass('gcp-analytics-003', 'No active Dataflow jobs found', check_cmd_str3))

    # Check 4: Pub/Sub topics without CMEK
    cmd4 = f'gcloud pubsub topics list --project={project_id} --format=json'
    stdout4, _, rc4 = run_cmd(cmd4)
    check_cmd_str4 = cmd4
    if rc4 == 0 and stdout4 and stdout4 != '[]':
        try:
            topics = json.loads(stdout4)
        except json.JSONDecodeError:
            topics = []
        no_cmek_topics = [
            t.get('name', '').split('/')[-1] for t in topics
            if not t.get('kmsKeyName')
        ]
        if no_cmek_topics:
            findings.append(make_finding(
                'gcp-analytics-004', SEVERITY_MEDIUM,
                'Pub/Sub topic without CMEK',
                f'Topics without CMEK: {", ".join(no_cmek_topics[:5])}',
                check_cmd_str4,
                'Configure CMEK for Pub/Sub topics: '
                'gcloud pubsub topics update TOPIC --message-encryption-key=KEY_RESOURCE_NAME',
            ))
        else:
            findings.append(finding_pass('gcp-analytics-004', 'All Pub/Sub topics have CMEK configured', check_cmd_str4))
    else:
        findings.append(finding_pass('gcp-analytics-004', 'No Pub/Sub topics found or listing failed', check_cmd_str4))

    return findings


# ---------------------------------------------------------------------------
# Subsystem dispatcher — keyed by (platform, subsystem) so future platforms
# (e.g. aws) can register their own check functions here.
# ---------------------------------------------------------------------------

PLATFORM_SUBSYSTEM_CHECKS = {
    'gcp': {
        'iam': check_gcp_iam,
        'compute': check_gcp_compute,
        'network': check_gcp_network,
        'storage': check_gcp_storage,
        'functions': check_gcp_functions,
        'databases': check_gcp_databases,
        'analytics': check_gcp_analytics,
    },
}


def run_subsystem(platform, subsystem, project_id, audit_id, audit_dir, timestamp):
    check_fn = PLATFORM_SUBSYSTEM_CHECKS.get(platform, {}).get(subsystem)
    if check_fn is None:
        print(f'  [SKIP] No {platform}/{subsystem} checks implemented', file=sys.stderr)
        return None

    print(f'  Checking {platform}/{subsystem}...', flush=True)
    findings = check_fn(project_id)

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
        print(f'\n{total_fail} finding(s) require attention. Run: /sectool remediate {audit_id}')
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
    audit_id = args.audit_id or f'{timestamp_str}-audit'
    iso_timestamp = datetime.now(timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ')

    # Resolve .audits directory relative to CWD
    audits_root = Path('.audits')
    audit_dir = audits_root / audit_id
    audit_dir.mkdir(parents=True, exist_ok=True)

    # Pre-flight: gcloud auth
    active_account = check_gcloud_auth()
    project_id = get_active_project()

    print(f'Auditing project : {project_id}')
    print(f'Account          : {active_account}')
    print(f'Audit ID         : {audit_id}')
    print(f'Output directory : {audit_dir}')
    print(f'Platforms        : {args.platforms}')
    print(f'Subsystems       : {args.subsystems}')
    print()

    all_results = {}

    for platform in args.platforms:
        for subsystem in args.subsystems:
            findings = run_subsystem(platform, subsystem, project_id, audit_id, audit_dir, iso_timestamp)
            if findings is not None:
                all_results[f'{platform}/{subsystem}'] = findings

    print_summary(audit_id, all_results)


if __name__ == '__main__':
    main()
