<?php
/**
 * MaurinDesk — Landing Page do Projeto e Servidor de Sinalização
 * Software de Acesso e Suporte Remoto Assistido (Open Source)
 */
declare(strict_types=1);

$apiHealthUrl = 'api/health';
$apiStatus = 'Verificando...';
$apiVersion = '0.5';
$healthData = null;

// Tenta verificar status local da API
if (file_exists(__DIR__ . '/api/Schema.php')) {
    require_once __DIR__ . '/api/Schema.php';
    $apiVersion = \MaurinDesk\Schema::VERSION;
}
?>
<!DOCTYPE html>
<html lang="pt-BR">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>MaurinDesk — Conexão Remota Assistida e Segura</title>
    <link rel="preconnect" href="https://fonts.googleapis.com">
    <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
    <link href="https://fonts.googleapis.com/css2?family=Inter:wght@300;400;500;600;700;800&display=swap" rel="stylesheet">
    <style>
        :root {
            --primary: #EF4444;
            --primary-dark: #DC2626;
            --primary-light: #FEE2E2;
            --secondary: #1E293B;
            --text-main: #0F172A;
            --text-muted: #64748B;
            --bg-page: #F8FAFC;
            --bg-card: #FFFFFF;
            --border-card: #E2E8F0;
            --accent-green: #10B981;
            --accent-blue: #0284C7;
        }
        * { box-sizing: border-box; margin: 0; padding: 0; font-family: 'Inter', system-ui, -apple-system, sans-serif; }
        body { background: var(--bg-page); color: var(--text-main); line-height: 1.6; }
        .container { max-width: 1140px; margin: 0 auto; padding: 0 20px; }
        
        /* Header */
        header { background: var(--bg-card); border-bottom: 1px solid var(--border-card); position: sticky; top: 0; z-index: 100; }
        .nav-inner { display: flex; align-items: center; justify-content: space-between; height: 72px; }
        .logo-box { display: flex; align-items: center; gap: 12px; text-decoration: none; color: inherit; }
        .logo-diamond { width: 36px; height: 36px; background: var(--primary); transform: rotate(45deg); border-radius: 8px; position: relative; box-shadow: 0 4px 12px rgba(239,68,68,0.3); }
        .logo-diamond::after { content: ''; position: absolute; width: 14px; height: 14px; background: white; top: 11px; left: 11px; border-radius: 3px; }
        .logo-text { font-size: 22px; font-weight: 800; letter-spacing: -0.5px; }
        .logo-text span { color: var(--primary); }
        .badge-version { background: var(--primary-light); color: var(--primary-dark); font-size: 12px; font-weight: 700; padding: 3px 8px; border-radius: 12px; margin-left: 8px; }
        .nav-links { display: flex; align-items: center; gap: 24px; }
        .nav-link { color: var(--text-muted); text-decoration: none; font-size: 14px; font-weight: 500; transition: color 0.2s; }
        .nav-link:hover { color: var(--primary); }
        .btn-header { background: var(--primary); color: white; padding: 10px 20px; border-radius: 8px; text-decoration: none; font-size: 14px; font-weight: 600; transition: background 0.2s, transform 0.1s; }
        .btn-header:hover { background: var(--primary-dark); transform: translateY(-1px); }

        /* Hero */
        .hero { padding: 80px 0 60px; text-align: center; }
        .hero-tagline { display: inline-flex; align-items: center; gap: 8px; background: #EEF2F6; color: #475569; font-size: 13px; font-weight: 600; padding: 6px 16px; border-radius: 20px; margin-bottom: 24px; }
        .hero-tagline-dot { width: 8px; height: 8px; border-radius: 50%; background: var(--accent-green); }
        .hero h1 { font-size: 48px; font-weight: 800; letter-spacing: -1.5px; line-height: 1.15; margin-bottom: 20px; color: var(--secondary); }
        .hero h1 span { color: var(--primary); }
        .hero p { font-size: 18px; color: var(--text-muted); max-width: 720px; margin: 0 auto 36px; }
        .hero-actions { display: flex; justify-content: center; gap: 16px; flex-wrap: wrap; }
        .btn-primary { background: var(--primary); color: white; padding: 14px 28px; border-radius: 10px; font-weight: 600; text-decoration: none; display: inline-flex; align-items: center; gap: 8px; box-shadow: 0 4px 16px rgba(239,68,68,0.25); transition: all 0.2s; }
        .btn-primary:hover { background: var(--primary-dark); transform: translateY(-2px); box-shadow: 0 6px 20px rgba(239,68,68,0.35); }
        .btn-secondary { background: white; border: 1px solid var(--border-card); color: var(--secondary); padding: 14px 28px; border-radius: 10px; font-weight: 600; text-decoration: none; display: inline-flex; align-items: center; gap: 8px; transition: all 0.2s; }
        .btn-secondary:hover { background: #F1F5F9; border-color: #CBD5E1; }

        /* Highlights Grid */
        .grid-3 { display: grid; grid-template-columns: repeat(auto-fit, minmax(320px, 1fr)); gap: 24px; margin-bottom: 60px; }
        .card { background: var(--bg-card); border: 1px solid var(--border-card); border-radius: 16px; padding: 32px; transition: all 0.2s; box-shadow: 0 2px 4px rgba(0,0,0,0.02); }
        .card:hover { transform: translateY(-4px); box-shadow: 0 12px 24px rgba(0,0,0,0.06); border-color: #CBD5E1; }
        .card-icon { width: 48px; height: 48px; border-radius: 12px; display: flex; align-items: center; justify-content: center; font-size: 24px; margin-bottom: 20px; }
        .icon-red { background: var(--primary-light); color: var(--primary); }
        .icon-green { background: #D1FAE5; color: var(--accent-green); }
        .icon-blue { background: #E0F2FE; color: var(--accent-blue); }
        .card h3 { font-size: 20px; font-weight: 700; margin-bottom: 12px; color: var(--secondary); }
        .card p { color: var(--text-muted); font-size: 15px; }

        /* Architecture Section */
        .section-box { background: white; border: 1px solid var(--border-card); border-radius: 20px; padding: 48px; margin-bottom: 60px; }
        .section-header { text-align: center; margin-bottom: 40px; }
        .section-header h2 { font-size: 32px; font-weight: 800; color: var(--secondary); margin-bottom: 8px; }
        .section-header p { color: var(--text-muted); font-size: 16px; }
        
        .steps-flow { display: grid; grid-template-columns: repeat(auto-fit, minmax(240px, 1fr)); gap: 24px; position: relative; }
        .step-item { background: #F8FAFC; border: 1px solid var(--border-card); border-radius: 12px; padding: 24px; text-align: center; position: relative; }
        .step-num { width: 32px; height: 32px; background: var(--secondary); color: white; border-radius: 50%; display: flex; align-items: center; justify-content: center; font-weight: 700; font-size: 14px; margin: 0 auto 16px; }
        .step-item h4 { font-size: 16px; font-weight: 700; margin-bottom: 8px; color: var(--secondary); }
        .step-item p { font-size: 13px; color: var(--text-muted); }

        /* API Status Banner */
        .api-banner { background: var(--secondary); color: white; border-radius: 16px; padding: 36px; display: flex; align-items: center; justify-content: space-between; flex-wrap: wrap; gap: 20px; margin-bottom: 60px; }
        .api-banner h3 { font-size: 22px; font-weight: 700; margin-bottom: 6px; }
        .api-banner p { color: #94A3B8; font-size: 14px; }
        .api-code { background: #0F172A; padding: 12px 20px; border-radius: 8px; font-family: monospace; font-size: 14px; color: #38BDF8; border: 1px solid #334155; }
        .api-badge { display: inline-flex; align-items: center; gap: 6px; background: rgba(16,185,129,0.2); color: #34D399; padding: 4px 10px; border-radius: 20px; font-size: 12px; font-weight: 600; }

        /* Footer */
        footer { border-top: 1px solid var(--border-card); padding: 40px 0; background: white; text-align: center; color: var(--text-muted); font-size: 14px; }
        footer a { color: var(--primary); text-decoration: none; font-weight: 600; }
        footer a:hover { text-decoration: underline; }
    </style>
</head>
<body>

    <!-- Header -->
    <header>
        <div class="container nav-inner">
            <a href="#" class="logo-box">
                <div class="logo-diamond"></div>
                <div class="logo-text">Maurin<span>Desk</span></div>
                <span class="badge-version">v<?= htmlspecialchars($apiVersion) ?></span>
            </a>
            <nav class="nav-links">
                <a href="#sobre" class="nav-link">Sobre</a>
                <a href="#arquitetura" class="nav-link">Arquitetura</a>
                <a href="#api" class="nav-link">API Nuvem</a>
                <a href="https://github.com/marcelomaurin/MaurinDesk" target="_blank" class="btn-header">GitHub Repository</a>
            </nav>
        </div>
    </header>

    <main class="container">
        <!-- Hero Section -->
        <section class="hero" id="sobre">
            <div class="hero-tagline">
                <span class="hero-tagline-dot"></span>
                Software Livre de Conexão e Suporte Remoto Assistido
            </div>
            <h1>Acesso Remoto Rápido, Seguro e <span>Ponto a Ponto</span></h1>
            <p>
                O <strong>MaurinDesk</strong> é uma solução independente inspirada no AnyDesk, construída com o poder nativo do 
                <strong>Free Pascal / Lazarus</strong> no cliente desktop e uma infraestrutura leve e robusta em <strong>PHP e MySQL</strong> para sinalização e consentimento.
            </p>
            <div class="hero-actions">
                <a href="https://github.com/marcelomaurin/MaurinDesk" target="_blank" class="btn-primary">
                    <svg width="20" height="20" fill="currentColor" viewBox="0 0 24 24"><path d="M12 0c-6.626 0-12 5.373-12 12 0 5.302 3.438 9.8 8.207 11.387.599.111.793-.261.793-.577v-2.234c-3.338.726-4.033-1.416-4.033-1.416-.546-1.387-1.333-1.756-1.333-1.756-1.089-.745.083-.729.083-.729 1.205.084 1.839 1.237 1.839 1.237 1.07 1.834 2.807 1.304 3.492.997.107-.775.418-1.305.762-1.604-2.665-.305-5.467-1.334-5.467-5.931 0-1.311.469-2.381 1.236-3.221-.124-.303-.535-1.524.117-3.176 0 0 1.008-.322 3.301 1.23.957-.266 1.983-.399 3.003-.404 1.02.005 2.047.138 3.006.404 2.291-1.552 3.297-1.23 3.297-1.23.653 1.653.242 2.874.118 3.176.77.84 1.235 1.911 1.235 3.221 0 4.609-2.807 5.624-5.479 5.921.43.372.823 1.102.823 2.222v3.293c0 .319.192.694.801.576 4.765-1.589 8.199-6.086 8.199-11.386 0-6.627-5.373-12-12-12z"/></svg>
                    Ver Código no GitHub
                </a>
                <a href="api/health" target="_blank" class="btn-secondary">
                    🔍 Verificar Status da API
                </a>
            </div>
        </section>

        <!-- Highlights Grid -->
        <section class="grid-3">
            <div class="card">
                <div class="card-icon icon-red">🛡️</div>
                <h3>Consentimento Estrito</h3>
                <p>Nenhuma sessão se inicia sem a autorização ativa da máquina que recebe o suporte. O anfitrião pode escolher entre conceder <strong>Controle Total</strong> ou <strong>Apenas Visualização</strong>.</p>
            </div>
            <div class="card">
                <div class="card-icon icon-green">⚡</div>
                <h3>P2P Direto (LAN + WAN)</h3>
                <p>Priorização automática de rede local para conexões ultrarrápidas na mesma empresa ou residência, com fallback transparente para endereços públicos via internet.</p>
            </div>
            <div class="card">
                <div class="card-icon icon-blue">🌐</div>
                <h3>Multi-idioma & Diagnósticos</h3>
                <p>Interface com suporte completo a Português, Inglês e Espanhol, além de envio automático e sob demanda de relatórios de falha para diagnóstico imediato no servidor.</p>
            </div>
        </section>

        <!-- Architecture Flow -->
        <section class="section-box" id="arquitetura">
            <div class="section-header">
                <h2>Como Funciona a Arquitetura</h2>
                <p>Segurança do início ao fim: o servidor coordena presença, mas nunca intercepta telas ou teclas.</p>
            </div>
            <div class="steps-flow">
                <div class="step-item">
                    <div class="step-num">1</div>
                    <h4>Identidade Criptográfica</h4>
                    <p>Cada computador recebe uma chave pública Ed25519 e uma Chave Desk de 10 dígitos (ex: <code>785 211 9103</code>) gerada localmente.</p>
                </div>
                <div class="step-item">
                    <div class="step-num">2</div>
                    <h4>Presença & Sinalização</h4>
                    <p>Os clientes anunciam sua presença via Heartbeat seguro para a API REST central hospedada no servidor na nuvem.</p>
                </div>
                <div class="step-item">
                    <div class="step-num">3</div>
                    <h4>Negociação de Consentimento</h4>
                    <p>Ao solicitar conexão, o anfitrião recebe um alerta visual e autoriza o acesso antes de qualquer troca de dados de tela.</p>
                </div>
                <div class="step-item">
                    <div class="step-num">4</div>
                    <h4>Streaming JPEG / TCP</h4>
                    <p>O fluxo de quadros (~15 FPS) e comandos de teclado/mouse é transmitido diretamente entre as duas máquinas via TCP nativo.</p>
                </div>
            </div>
        </section>

        <!-- API Endpoint Banner -->
        <section class="api-banner" id="api">
            <div>
                <div class="api-badge">● API Online</div>
                <h3>Serviço Central de Sinalização MaurinDesk</h3>
                <p>Endpoint REST JSON oficial disponível para clientes de desktop e integrações.</p>
            </div>
            <div class="api-code">
                GET https://maurinsoft.com.br/MaurinDesk/api/health
            </div>
        </section>
    </main>

    <!-- Footer -->
    <footer>
        <div class="container">
            <p>MaurinDesk — Desenvolvido por <strong>Marcelo Maurin Martins</strong> &copy; <?= date('Y') ?></p>
            <p style="margin-top: 8px;">
                <a href="https://maurinsoft.com.br">maurinsoft.com.br</a> &bull; 
                <a href="https://github.com/marcelomaurin/MaurinDesk">GitHub</a> &bull; 
                <a href="api/health">Status da API (v<?= htmlspecialchars($apiVersion) ?>)</a>
            </p>
        </div>
    </footer>

</body>
</html>
