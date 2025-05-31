#!/bin/bash


# Sair imediatamente se um comando sair com status diferente de zero.
set -e
# Tratar erros em pipelines (e.g., cmd1 | cmd2) como falha se qualquer comando falhar.
set -o pipefail

# --- Variáveis ---
IMAGE_NAME="umbrel"

# --- Funções ---

# Verifica se o Docker já está instalado
check_docker_installed() {
    if command -v docker &> /dev/null; then
        return 0 # true, Docker encontrado
    else
        return 1 # false, Docker não encontrado
    fi
}

# Instala Docker usando DNF (para Fedora, CentOS Stream, RHEL)
install_docker_dnf() {
    echo "INFO: Instalando Docker Engine com DNF..."
    # Adicionar repositório oficial do Docker
    dnf install -y dnf-plugins-core
    # Usando o repositório do Fedora como padrão. Para CentOS/RHEL, o link pode precisar ser ajustado.
    # Ex: https://download.docker.com/linux/centos/docker-ce.repo
    dnf config-manager --add-repo https://download.docker.com/linux/fedora/docker-ce.repo
    
    # Instalar Docker Engine, CLI, Containerd e plugins
    dnf install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    
    echo "INFO: Iniciando e habilitando o serviço Docker..."
    systemctl start docker
    systemctl enable docker
    echo "INFO: Docker instalado e configurado com DNF."
}

# Instala Docker usando Pacman (para Arch Linux)
install_docker_pacman() {
    echo "INFO: Instalando Docker com Pacman..."
    pacman -Syu --noconfirm --needed docker docker-compose
    
    echo "INFO: Iniciando e habilitando o serviço Docker..."
    systemctl start docker
    systemctl enable docker
    echo "INFO: Docker instalado e configurado com Pacman."
}

# Instala Docker usando APT (para Debian, Ubuntu)
install_docker_apt() {
    echo "INFO: Instalando Docker Engine com APT..."
    # Desinstalar versões antigas, se existirem (ignorar erros se não existirem)
    for pkg in docker.io docker-doc docker-compose podman-docker containerd runc; do apt-get remove -y $pkg 2>/dev/null || true; done

    # Configurar o repositório do Docker
    apt-get update -y
    apt-get install -y ca-certificates curl gnupg
    
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL "https://download.docker.com/linux/$(. /etc/os-release && echo "$ID")/gpg" | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    chmod a+r /etc/apt/keyrings/docker.gpg
    
    echo \
      "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/$(. /etc/os-release && echo "$ID") \
      $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
      
    # Instalar Docker Engine
    apt-get update -y
    apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    
    echo "INFO: Iniciando e habilitando o serviço Docker..."
    # O serviço Docker geralmente inicia automaticamente após a instalação em sistemas baseados em Debian/Ubuntu.
    # Mas vamos garantir que esteja iniciado e habilitado.
    systemctl start docker
    systemctl enable docker
    echo "INFO: Docker instalado e configurado com APT."
}

# --- Script Principal ---
echo "--- Iniciando script de automação do Docker ---"
echo

# 1. Verificar privilégios de root
echo "PASSO 1: Verificando privilégios de root..."
if [ "$EUID" -ne 0 ]; then
  echo "ERRO: Este script precisa ser executado como root."
  echo "Use: sudo $0"
  exit 1
fi
echo "INFO: Executando como root."
echo

# 2. Verificar se o Docker já está instalado
echo "PASSO 2: Verificando se o Docker já está instalado..."
if check_docker_installed; then
    echo "INFO: Docker já está instalado no sistema."
else
    echo "INFO: Docker não encontrado. Tentando instalar..."
    
    if command -v dnf &> /dev/null; then
        echo "INFO: Detectado gerenciador de pacotes DNF (Fedora/RHEL/CentOS)."
        install_docker_dnf
    elif command -v pacman &> /dev/null; then
        echo "INFO: Detectado gerenciador de pacotes Pacman (Arch Linux)."
        install_docker_pacman
    elif command -v apt-get &> /dev/null; then
        echo "INFO: Detectado gerenciador de pacotes APT (Debian/Ubuntu)."
        install_docker_apt
    else
        echo "AVISO: Nenhum gerenciador de pacotes suportado (dnf, pacman, apt) foi detectado."
        echo "Por favor, instale o Docker manualmente para o seu sistema operacional."
        echo "Instruções podem ser encontradas em: https://docs.docker.com/engine/install/"
        exit 1
    fi

    # Verifica novamente se a instalação foi bem-sucedida
    if ! check_docker_installed; then
        echo "ERRO: Falha crítica ao instalar o Docker. Verifique os logs acima."
        echo "Considere tentar a instalação manual seguindo a documentação oficial."
        exit 1
    else
        echo "INFO: Docker instalado com sucesso!"
    fi
fi
echo

# 3. Garantir que o serviço Docker esteja rodando e habilitado
echo "PASSO 3: Verificando e garantindo o status do serviço Docker..."
if ! systemctl is-active --quiet docker; then
    echo "INFO: Serviço Docker não está ativo. Iniciando..."
    systemctl start docker
    sleep 3 # Aguarda um pouco para o serviço iniciar completamente
    if ! systemctl is-active --quiet docker; then
        echo "ERRO: Não foi possível iniciar o serviço Docker. Verifique a instalação e os logs do sistema (journalctl -u docker.service)."
        exit 1
    fi
    echo "INFO: Serviço Docker iniciado com sucesso."
else
    echo "INFO: Serviço Docker já está ativo."
fi

if ! systemctl is-enabled --quiet docker; then
    echo "INFO: Serviço Docker não está habilitado para iniciar no boot. Habilitando..."
    systemctl enable docker
    echo "INFO: Docker habilitado para iniciar no boot."
else
    echo "INFO: Docker já está habilitado para iniciar no boot."
fi
echo

# 4. Baixar a imagem Docker especificada
echo "PASSO 4: Baixando a imagem Docker umbrel"
if docker pull umbrel; then
    echo "INFO: Imagem umbrel baixada com sucesso."
else
    echo "ERRO: Falha ao baixar a imagem umbrel
    echo "Verifique sua conexão com a internet e a configuração do Docker ex: DNS, proxy."
    exit 1
fi
echo

# 5. Rodar o container Docker
echo "PASSO 5: Rodando o container umbrel..."
if docker run -it --rm --name umbrel --pid=host -p 80:80 -v "${PWD:-.}/umbrel:/data" -v "/var/run/docker.sock:/var/run/docker.sock" --stop-timeout 60 dockurr/umbrel ; then
    echo
    echo "INFO: Container '$IMAGE_NAME' executado com sucesso!"
else
    echo "ERRO: Falha ao executar o container '$IMAGE_NAME'."
    exit 1
fi
echo

echo "--- Script finalizado com sucesso ---"
exit 0
