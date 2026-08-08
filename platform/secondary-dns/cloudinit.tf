locals {
  management_ipv4 = split("/", var.management.ipv4_cidr)[0]
  management_ipv6 = split("/", var.management.ipv6_cidr)[0]
  dns_ipv4        = split("/", var.dns_internal.ipv4_cidr)[0]
  dns_ipv6        = split("/", var.dns_internal.ipv6_cidr)[0]
  ntp_ipv4        = split("/", var.ntp_internal.ipv4_cidr)[0]
  ntp_ipv6        = split("/", var.ntp_internal.ipv6_cidr)[0]
  public_ipv4     = split("/", var.public.ipv4_cidr)[0]
  public_ipv6     = split("/", var.public.ipv6_cidr)[0]

  internal_ipv4_networks = sort([for network in var.primary_router.trusted_internal_networks : network if !strcontains(network, ":")])
  internal_ipv6_networks = sort([for network in var.primary_router.trusted_internal_networks : network if strcontains(network, ":")])

  network_data = yamlencode({
    version = 2
    ethernets = {
      mgmt0 = {
        match = {
          macaddress = lower(var.management_mac)
        }
        set-name  = "mgmt0"
        dhcp4     = false
        dhcp6     = false
        addresses = [var.management.ipv4_cidr, var.management.ipv6_cidr]
        routes = [
          { to = cidrsubnet(var.management.ipv4_cidr, 0, 0), scope = "link", table = var.management.vlan_id },
          { to = "0.0.0.0/0", via = var.management.ipv4_gateway, table = var.management.vlan_id },
          { to = cidrsubnet(var.management.ipv6_cidr, 0, 0), scope = "link", table = var.management.vlan_id },
          { to = "::/0", via = var.management.ipv6_gateway, table = var.management.vlan_id },
        ]
        "routing-policy" = [
          { from = "${local.management_ipv4}/32", table = var.management.vlan_id, priority = 10508 },
          { from = "${local.management_ipv6}/128", table = var.management.vlan_id, priority = 10509 },
        ]
      }
      trunk0 = {
        match = {
          macaddress = lower(var.trunk_mac)
        }
        set-name = "trunk0"
        dhcp4    = false
        dhcp6    = false
        optional = true
      }
    }
    vlans = {
      alcor = {
        id        = var.dns_internal.vlan_id
        link      = "trunk0"
        addresses = [var.dns_internal.ipv4_cidr, var.dns_internal.ipv6_cidr]
        nameservers = {
          addresses = [var.primary_router.internal_dns_ipv4]
        }
        routes = concat(
          [
            { to = cidrsubnet(var.dns_internal.ipv4_cidr, 0, 0), scope = "link", table = var.dns_internal.vlan_id },
            { to = "0.0.0.0/0", via = var.dns_internal.ipv4_gateway, table = var.dns_internal.vlan_id },
            { to = cidrsubnet(var.dns_internal.ipv6_cidr, 0, 0), scope = "link", table = var.dns_internal.vlan_id },
            { to = "::/0", via = var.dns_internal.ipv6_gateway, table = var.dns_internal.vlan_id },
          ],
          [for network in local.internal_ipv4_networks : { to = network, via = var.dns_internal.ipv4_gateway, metric = 50 }],
          [for network in local.internal_ipv6_networks : { to = network, via = var.dns_internal.ipv6_gateway, metric = 50 }],
        )
        "routing-policy" = [
          { from = "${local.dns_ipv4}/32", table = var.dns_internal.vlan_id, priority = 102804 },
          { from = "${local.dns_ipv6}/128", table = var.dns_internal.vlan_id, priority = 102805 },
        ]
      }
      kochab = {
        id        = var.ntp_internal.vlan_id
        link      = "trunk0"
        addresses = [var.ntp_internal.ipv4_cidr, var.ntp_internal.ipv6_cidr]
        routes = [
          { to = cidrsubnet(var.ntp_internal.ipv4_cidr, 0, 0), scope = "link", table = var.ntp_internal.vlan_id },
          { to = "0.0.0.0/0", via = var.ntp_internal.ipv4_gateway, table = var.ntp_internal.vlan_id },
          { to = cidrsubnet(var.ntp_internal.ipv6_cidr, 0, 0), scope = "link", table = var.ntp_internal.vlan_id },
          { to = "::/0", via = var.ntp_internal.ipv6_gateway, table = var.ntp_internal.vlan_id },
        ]
        "routing-policy" = [
          { from = "${local.ntp_ipv4}/32", table = var.ntp_internal.vlan_id, priority = 102820 },
          { from = "${local.ntp_ipv6}/128", table = var.ntp_internal.vlan_id, priority = 102821 },
        ]
      }
      public = {
        id        = local.public_transport.vlan_id
        link      = "trunk0"
        addresses = [var.public.ipv4_cidr, var.public.ipv6_cidr]
        routes = [
          { to = "0.0.0.0/0", via = local.public_transport.router_address, metric = 100 },
          { to = cidrsubnet(var.public.ipv4_cidr, 0, 0), scope = "link", table = local.public_transport.vlan_id },
          { to = "0.0.0.0/0", via = local.public_transport.router_address, table = local.public_transport.vlan_id },
          { to = "::/0", via = local.public_transport.router_ipv6_address, metric = 100 },
          { to = cidrsubnet(var.public.ipv6_cidr, 0, 0), scope = "link", table = local.public_transport.vlan_id },
          { to = "::/0", via = local.public_transport.router_ipv6_address, table = local.public_transport.vlan_id },
        ]
        "routing-policy" = [
          { from = "${local.public_ipv4}/32", table = local.public_transport.vlan_id, priority = 103802 },
          { from = "${local.public_ipv6}/128", table = local.public_transport.vlan_id, priority = 103803 },
        ]
      }
    }
  })

  bind_internal_acl           = join("; ", concat(local.internal_ipv4_networks, local.internal_ipv6_networks))
  bind_internal_recursion     = var.internal_recursion_enabled ? "yes" : "no"
  bind_internal_recursion_acl = var.internal_recursion_enabled ? "internal_clients" : "none"
  bind_options                = <<-EOT
    options {
        directory "/var/cache/bind";
        listen-on port 53 { ${local.dns_ipv4}; ${local.public_ipv4}; };
        listen-on-v6 port 53 { ${local.dns_ipv6}; ${local.public_ipv6}; };
        recursion no;
        allow-query { none; };
        dnssec-validation auto;
        auth-nxdomain no;
        minimal-responses yes;
        version "not disclosed";
        hostname "not disclosed";
        rate-limit { responses-per-second 20; };
    };
  EOT

  bind_main = <<-EOT
    include "/etc/bind/named.conf.options";
    include "/etc/bind/named.conf.local";
  EOT

  bind_local = <<-EOT
    key "${var.transfer_tsig_name}" {
        algorithm ${var.transfer_tsig_algorithm};
        secret "${var.transfer_tsig_secret}";
    };

    acl "internal_clients" { ${local.bind_internal_acl}; };

    view "internal" {
        match-clients { internal_clients; };
        match-destinations { ${local.dns_ipv4}; ${local.dns_ipv6}; };
        recursion ${local.bind_internal_recursion};
        allow-query { internal_clients; };
        allow-recursion { ${local.bind_internal_recursion_acl}; };
        transfer-source ${local.dns_ipv4};
        transfer-source-v6 ${local.dns_ipv6};

        zone "${trimsuffix(var.primary_router.zone_name, ".")}" {
            type secondary;
            primaries { ${var.primary_router.internal_dns_ipv4} key "${var.transfer_tsig_name}"; };
            allow-notify { ${var.dns_internal.ipv4_gateway}; };
            file "/var/cache/bind/internal/${trimsuffix(var.primary_router.zone_name, ".")}.db";
        };
    };

    view "public" {
        match-clients { any; };
        match-destinations { ${local.public_ipv4}; ${local.public_ipv6}; };
        recursion no;
        allow-query { any; };
        transfer-source ${local.public_ipv4};
        transfer-source-v6 ${local.public_ipv6};

        zone "${trimsuffix(var.primary_router.zone_name, ".")}" {
            type secondary;
            primaries { ${var.primary_router.public_dns_ipv4} key "${var.transfer_tsig_name}"; };
            allow-notify { ${local.public_transport.router_address}; };
            file "/var/cache/bind/public/${trimsuffix(var.primary_router.zone_name, ".")}.db";
        };
    };
  EOT

  chrony_config = join("\n", concat(
    [for upstream in sort(tolist(var.ntp_upstreams)) : "pool ${upstream} iburst maxsources 2"],
    [
      "driftfile /var/lib/chrony/chrony.drift",
      "makestep 1.0 3",
      "rtcsync",
      "bindaddress ${local.ntp_ipv4}",
      "bindaddress ${local.ntp_ipv6}",
      "cmdport 0",
    ],
    [for network in local.internal_ipv4_networks : "allow ${network}"],
    [for network in local.internal_ipv6_networks : "allow ${network}"],
    [""]
  ))

  nft_internal_v4 = join(", ", local.internal_ipv4_networks)
  nft_internal_v6 = join(", ", local.internal_ipv6_networks)
  nftables_config = <<-EOT
    flush ruleset

    table inet filter {
      set internal_v4 {
        type ipv4_addr
        flags interval
        elements = { ${local.nft_internal_v4} }
      }
      set internal_v6 {
        type ipv6_addr
        flags interval
        elements = { ${local.nft_internal_v6} }
      }

      chain input {
        type filter hook input priority 0; policy drop;
        iifname "lo" accept
        ct state established,related accept
        ip protocol icmp accept
        ip6 nexthdr ipv6-icmp accept

        iifname "mgmt0" ip saddr @internal_v4 tcp dport 22 accept
        iifname "mgmt0" ip6 saddr @internal_v6 tcp dport 22 accept

        iifname "alcor" ip saddr @internal_v4 udp dport 53 accept
        iifname "alcor" ip saddr @internal_v4 tcp dport 53 accept
        iifname "alcor" ip6 saddr @internal_v6 udp dport 53 accept
        iifname "alcor" ip6 saddr @internal_v6 tcp dport 53 accept

        iifname "kochab" ip saddr @internal_v4 udp dport 123 accept
        iifname "kochab" ip6 saddr @internal_v6 udp dport 123 accept

        iifname "public" udp dport 53 accept
        iifname "public" tcp dport 53 accept
      }

      chain forward {
        type filter hook forward priority 0; policy drop;
      }

      chain output {
        type filter hook output priority 0; policy accept;
      }
    }
  EOT

  ssh_config = <<-EOT
    PasswordAuthentication no
    KbdInteractiveAuthentication no
    PermitRootLogin no
    X11Forwarding no
  EOT

  user_data = <<-EOT
    #cloud-config
    ${yamlencode({
  hostname         = "rigi"
  fqdn             = "rigi.host.biptec.net"
  manage_etc_hosts = true
  package_update   = true
  package_upgrade  = false
  ssh_pwauth       = false
  disable_root     = true
  users = [
    merge(
      {
        name        = "ubuntu"
        groups      = ["adm", "sudo"]
        shell       = "/bin/bash"
        sudo        = "ALL=(ALL) NOPASSWD:ALL"
        lock_passwd = true
      },
      var.ssh_public_key == null ? {} : {
        ssh_authorized_keys = [trimspace(var.ssh_public_key)]
      },
    )
  ]
  bootcmd = [
    ["sh", "-c", "printf '#!/bin/sh\\nexit 101\\n' > /usr/sbin/policy-rc.d && chmod 0755 /usr/sbin/policy-rc.d"],
  ]
  packages = [
    "bind9",
    "bind9-utils",
    "chrony",
    "nftables",
    "qemu-guest-agent",
    "openssh-server",
  ]
  write_files = [
    { path = "/etc/bind/named.conf", permissions = "0644", owner = "root:root", content = local.bind_main, defer = true },
    { path = "/etc/bind/named.conf.options", permissions = "0644", owner = "root:root", content = local.bind_options, defer = true },
    { path = "/etc/bind/named.conf.local", permissions = "0640", owner = "root:bind", content = local.bind_local, defer = true },
    { path = "/etc/chrony/chrony.conf", permissions = "0644", owner = "root:root", content = local.chrony_config, defer = true },
    { path = "/etc/nftables.conf", permissions = "0600", owner = "root:root", content = local.nftables_config, defer = true },
    { path = "/etc/ssh/sshd_config.d/90-platform-hardening.conf", permissions = "0644", owner = "root:root", content = local.ssh_config, defer = true },
  ]
  runcmd = [
    ["sh", "-ec", join("\n", [
      "mkdir -p /var/cache/bind/internal /var/cache/bind/public",
      "chown -R bind:bind /var/cache/bind/internal /var/cache/bind/public",
      "named-checkconf",
      "nft -c -f /etc/nftables.conf",
      "rm -f /usr/sbin/policy-rc.d",
      "systemctl enable --now nftables.service",
      "systemctl enable --now named.service",
      "systemctl enable --now chrony.service",
      "systemctl start qemu-guest-agent.service",
      "systemctl reload ssh.service",
      "systemctl is-active --quiet named",
      "systemctl is-active --quiet chrony",
      "systemctl is-active --quiet nftables",
      "systemctl is-active --quiet qemu-guest-agent",
      "touch /var/lib/rigi-bootstrap.done",
    ])],
  ]
})}
  EOT

config_revision = sha256(join("\n---\n", [
  local.network_data,
  nonsensitive(local.user_data),
  var.image.sha256,
]))
}
