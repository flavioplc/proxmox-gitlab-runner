# Proxmox VE — GitLab Runner LXC

Script de création d'un conteneur LXC **GitLab Runner** pour Proxmox VE, écrit sur le modèle des
[Proxmox VE Helper-Scripts](https://github.com/community-scripts/ProxmoxVE) (même structure que le script
`Forgejo-Runner`). La collection communautaire propose un script pour GitLab, mais pas pour son runner.

Le conteneur obtenu :

- Debian 13, LXC **non privilégié** avec `nesting=1` et `keyctl=1`
- 2 vCPU, 2 Go de RAM, 20 Go de disque par défaut
- Docker (`docker.io`) comme moteur pour l'executor `docker`
- GitLab Runner installé depuis le binaire officiel dans `/usr/local/bin/gitlab-runner`
- runner enregistré automatiquement auprès de ton instance et lancé par un service systemd

## Contenu

| Fichier | Rôle |
|---|---|
| `ct/gitlab-runner.sh` | Exécuté sur l'hôte Proxmox : crée le LXC et gère les mises à jour |
| `install/gitlab-runner-install.sh` | Exécuté dans le LXC : installe Docker et le runner, puis l'enregistre |

## Prérequis

- Proxmox VE 8.4 ou 9.x
- Un **token d'authentification de runner** (`glrt-…`). Il se crée dans GitLab, dans
  *Settings → CI/CD → Runners → New project runner* (ou au niveau d'un groupe ou de l'instance).
  Les tags, le mode protégé et l'option « run untagged » se règlent à ce moment-là dans GitLab :
  avec ce type de token, ils ne peuvent pas être passés au moment de l'enregistrement.

## Installation

Le script `ct/` charge le moteur des community-scripts, qui récupère ensuite `install/gitlab-runner-install.sh`
depuis le dépôt désigné par `COMMUNITY_SCRIPTS_URL`. Comme ce script n'est pas dans la collection officielle,
cette variable doit pointer vers ce dépôt-ci.

Dans le shell de l'hôte Proxmox :

```bash
export COMMUNITY_SCRIPTS_URL=https://raw.githubusercontent.com/flavioplc/proxmox-gitlab-runner/main
bash -c "$(curl -fsSL "$COMMUNITY_SCRIPTS_URL/ct/gitlab-runner.sh")"
```

> ⚠️ N'utilise pas la forme `curl … | bash` (ni le lanceur `run.sh` de community-scripts/core, qui s'utilise
> de cette façon) : l'entrée standard est alors le pipe et non le terminal, et les questions posées dans le
> conteneur échouent immédiatement. La forme `bash -c "$(curl …)"` garde le terminal comme entrée.

Le script demande :

1. l'URL de l'instance GitLab (par défaut `https://gitlab.com`) ;
2. le token `glrt-…` (saisie masquée) ;
3. l'image Docker utilisée par défaut pour les jobs (par défaut `alpine:latest`).

Le runner doit ensuite apparaître comme connecté dans *Settings → CI/CD → Runners*.

### Installation sans questions

Toutes les valeurs peuvent être fournies par variables d'environnement :

| Variable | Défaut | Description |
|---|---|---|
| `var_gitlab_url` | — (obligatoire) | URL de l'instance GitLab |
| `var_gitlab_runner_token` | — (obligatoire) | Token d'authentification `glrt-…` |
| `var_gitlab_runner_image` | `alpine:latest` | Image Docker par défaut des jobs |
| `var_gitlab_runner_concurrent` | `2` | Nombre de jobs simultanés (`concurrent` dans `config.toml`) |
| `var_cpu` / `var_ram` / `var_disk` | `2` / `2048` / `20` | Ressources du conteneur |

## Mise à jour

Relance les deux mêmes commandes, mais **depuis la console du conteneur** et non depuis l'hôte :
le script détecte qu'il tourne dans le LXC et passe en mode mise à jour. Il compare la version installée
avec la dernière release de GitLab Runner et remplace le binaire si besoin. La configuration (`/etc/gitlab-runner/config.toml`)
est conservée.

## Limites

- **Construction d'images Docker dans les jobs** (`docker build`, Docker-in-Docker) : il faut
  `privileged = true` dans `config.toml`, ce qui fonctionne mal dans un LXC non privilégié. Utilise plutôt
  Kaniko ou Buildah dans les jobs, ou fais tourner le runner dans une VM.
- **Stockage ZFS** : Docker dans un LXC sur ZFS utilise `overlay2`, ce qui nécessite OpenZFS 2.2 ou plus
  (Proxmox VE 8.1+).
- **arm64** : non testé, le script ne force pas le support.
- Les scripts n'ont pas encore été validés sur un vrai Proxmox. Teste-les sur un conteneur jetable
  avant de t'y fier.

## Configuration

- Configuration du runner : `/etc/gitlab-runner/config.toml`
- Logs : `journalctl -u gitlab-runner -f`
- Vérifier la connexion : `gitlab-runner verify`

## Licence

MIT, comme les [Proxmox VE Helper-Scripts](https://github.com/community-scripts/ProxmoxVE) dont ce script
reprend la structure.
