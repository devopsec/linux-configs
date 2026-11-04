# Hardened GCP network for SIP/RTP edges + private app tier.
# Replaces upstream terraform-gcp/assets/vpc-module.tf (which opened SSH and
# all internal ports to 0.0.0.0/0 / 10.0.0.0/8). Works with terraform and tofu.
# Copy into modules/network/ and wire variables from the root module.

terraform {
  required_version = ">= 1.6"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 8.0"
    }
  }
}

variable "project_id" {
  description = "GCP project ID."
  type        = string
}

variable "region" {
  description = "Region for subnets, router, NAT and static IPs."
  type        = string
}

variable "name_prefix" {
  description = "Prefix for all resource names, e.g. \"isen-prod\"."
  type        = string
}

variable "app_subnet_cidr" {
  description = "CIDR of the private application subnet (no external IPs, egress via Cloud NAT)."
  type        = string
  default     = "10.10.0.0/20"
}

variable "sip_subnet_cidr" {
  description = "CIDR of the SIP edge subnet (static external IPs, never NATed)."
  type        = string
  default     = "10.10.16.0/24"
}

variable "sip_peer_ranges" {
  description = "Carrier/trunk CIDRs allowed to send SIP signalling (UDP/TCP 5060, TLS 5061)."
  type        = list(string)

  validation {
    condition     = length(var.sip_peer_ranges) > 0 && !contains(var.sip_peer_ranges, "0.0.0.0/0")
    error_message = "Provide explicit peer CIDRs; 0.0.0.0/0 is not allowed for plain SIP."
  }
}

variable "media_peer_ranges" {
  description = "CIDRs allowed to send RTP media to the edges."
  type        = list(string)
}

variable "rtp_port_range" {
  description = "RTP UDP port range; must match rtpengine/Kamailio config (verify against platform config)."
  type        = string
  default     = "30000-40000"
}

variable "sip_edge_names" {
  description = "Names of SIP edge hosts that get a reserved static external IP."
  type        = set(string)
  default     = []
}

locals {
  iap_range        = "35.235.240.0/20"
  gcp_health_check = ["35.191.0.0/16", "130.211.0.0/22"]
}

resource "google_compute_network" "main" {
  project                 = var.project_id
  name                    = "${var.name_prefix}-vpc"
  auto_create_subnetworks = false
  routing_mode            = "REGIONAL"
}

resource "google_compute_subnetwork" "app" {
  project                  = var.project_id
  name                     = "${var.name_prefix}-app"
  region                   = var.region
  network                  = google_compute_network.main.id
  ip_cidr_range            = var.app_subnet_cidr
  private_ip_google_access = true

  log_config {
    aggregation_interval = "INTERVAL_5_SEC"
    flow_sampling        = 0.5
  }
}

resource "google_compute_subnetwork" "sip" {
  project                  = var.project_id
  name                     = "${var.name_prefix}-sip-edge"
  region                   = var.region
  network                  = google_compute_network.main.id
  ip_cidr_range            = var.sip_subnet_cidr
  private_ip_google_access = true

  log_config {
    aggregation_interval = "INTERVAL_5_SEC"
    flow_sampling        = 0.5
  }
}

resource "google_compute_firewall" "iap_ssh" {
  project       = var.project_id
  name          = "${var.name_prefix}-allow-iap-ssh"
  network       = google_compute_network.main.name
  direction     = "INGRESS"
  source_ranges = [local.iap_range]
  target_tags   = ["iap-ssh"]

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }
}

resource "google_compute_firewall" "health_checks" {
  project       = var.project_id
  name          = "${var.name_prefix}-allow-gcp-hc"
  network       = google_compute_network.main.name
  direction     = "INGRESS"
  source_ranges = local.gcp_health_check
  target_tags   = ["sip-edge", "isen-worker"]

  allow {
    protocol = "tcp"
    ports    = ["5060", "8080"]
  }
}

resource "google_compute_firewall" "sip_signalling" {
  project       = var.project_id
  name          = "${var.name_prefix}-allow-sip"
  network       = google_compute_network.main.name
  direction     = "INGRESS"
  priority      = 900
  source_ranges = var.sip_peer_ranges
  target_tags   = ["sip-edge"]

  allow {
    protocol = "udp"
    ports    = ["5060"]
  }

  allow {
    protocol = "tcp"
    ports    = ["5060", "5061"]
  }

  log_config {
    metadata = "INCLUDE_ALL_METADATA"
  }
}

resource "google_compute_firewall" "rtp_media" {
  project       = var.project_id
  name          = "${var.name_prefix}-allow-rtp"
  network       = google_compute_network.main.name
  direction     = "INGRESS"
  priority      = 900
  source_ranges = var.media_peer_ranges
  target_tags   = ["sip-edge"]

  allow {
    protocol = "udp"
    ports    = [var.rtp_port_range]
  }
}

resource "google_compute_firewall" "app_to_sip" {
  project     = var.project_id
  name        = "${var.name_prefix}-allow-app-to-sip"
  network     = google_compute_network.main.name
  direction   = "INGRESS"
  source_tags = ["isen-worker"]
  target_tags = ["sip-edge"]

  allow {
    protocol = "udp"
    ports    = ["5060"]
  }

  allow {
    protocol = "tcp"
    ports    = ["5060"]
  }
}

resource "google_compute_router" "main" {
  project = var.project_id
  name    = "${var.name_prefix}-router"
  region  = var.region
  network = google_compute_network.main.id
}

resource "google_compute_address" "nat" {
  project = var.project_id
  name    = "${var.name_prefix}-nat-ip"
  region  = var.region
}

# NAT only for the app subnet - SIP edges must not be NATed (breaks Via/Contact/SDP).
resource "google_compute_router_nat" "app" {
  project                             = var.project_id
  name                                = "${var.name_prefix}-nat"
  router                              = google_compute_router.main.name
  region                              = var.region
  nat_ip_allocate_option              = "MANUAL_ONLY"
  nat_ips                             = [google_compute_address.nat.self_link]
  source_subnetwork_ip_ranges_to_nat  = "LIST_OF_SUBNETWORKS"
  enable_dynamic_port_allocation      = true
  enable_endpoint_independent_mapping = false
  min_ports_per_vm                    = 128
  max_ports_per_vm                    = 4096

  subnetwork {
    name                    = google_compute_subnetwork.app.id
    source_ip_ranges_to_nat = ["ALL_IP_RANGES"]
  }

  log_config {
    enable = true
    filter = "ERRORS_ONLY"
  }
}

resource "google_compute_address" "sip_edge" {
  for_each = var.sip_edge_names

  project      = var.project_id
  name         = "${var.name_prefix}-${each.key}-ip"
  region       = var.region
  network_tier = "PREMIUM"

  lifecycle {
    prevent_destroy = true
  }
}

output "network_id" {
  description = "VPC self ID."
  value       = google_compute_network.main.id
}

output "subnet_ids" {
  description = "Subnet IDs by role."
  value = {
    app = google_compute_subnetwork.app.id
    sip = google_compute_subnetwork.sip.id
  }
}

output "sip_edge_ips" {
  description = "Reserved external IPs per SIP edge; use as Kamailio/rtpengine advertise address."
  value       = { for name, addr in google_compute_address.sip_edge : name => addr.address }
}

output "nat_ip" {
  description = "Stable egress IP of the app tier (for partner allow-lists)."
  value       = google_compute_address.nat.address
}
