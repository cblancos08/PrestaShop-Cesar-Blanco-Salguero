# -*- mode: ruby -*-
# vi: set ft=ruby :

# Quita los saltos de línea de Windows (\r) de los scripts antes de ejecutarlos
LIMPIAR_CRLF = "find /vagrant/scripts /vagrant/conf -type f \\( -name '*.sh' -o -name '*.conf' -o -name '.env' \\) -exec sed -i 's/\\r$//' {} + 2>/dev/null || true"

Vagrant.configure("2") do |config|
  config.vm.box = "bento/debian-12"

  config.vm.define "CesarBlancoPrestashop" do |ps|
    ps.vm.hostname = "CesarBlancoPrestashop"
    ps.vm.network "private_network", ip: "192.168.56.10"

    ps.vm.provider "virtualbox" do |vb|
      vb.name = "CesarBlancoPrestashop"
      vb.memory = 2048
      vb.cpus = 2
    end

    # Los tres scripts de aprovisionamiento solo se ejecutan cuando se piden por nombre
    ps.vm.provision "lamp", type: "shell", run: "never",
      inline: "#{LIMPIAR_CRLF} && bash /vagrant/scripts/install_lamp.sh"

    ps.vm.provision "https", type: "shell", run: "never",
      env: { "DUCKDNS_TOKEN" => ENV.fetch("DUCKDNS_TOKEN", "") },
      inline: "#{LIMPIAR_CRLF} && bash /vagrant/scripts/setup_letsencrypt_https.sh"

    ps.vm.provision "prestashop", type: "shell", run: "never",
      inline: "#{LIMPIAR_CRLF} && bash /vagrant/scripts/deploy_prestashop.sh"
  end
end
