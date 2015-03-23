{% set cfg = opts.ms_project %}
{% set data = cfg.data %}
{% set apacheSettings = salt['mc_apache.settings']() %}
{% set sdata = salt['mc_utils.json_dump'](cfg) %}
include:
  - makina-states.services.http.apache

{% set httpusers = {} %}
{% for users in data.get('http_users', []) %}
{% for user, pw in users.items() %}
{% do httpusers.update({user: pw}) %}
{% endfor %}
{% endfor %}

prepreq-{{cfg.name}}:
  pkg.{{salt['mc_pkgs.settings']()['installmode']}}:
    - pkgs:
      {# install the lib in dep this save us from naming diff
         packages between debian flavors #}
      - apache2-utils
      - websvn
      - libapache2-mod-svn
    - watch_in:
      - mc_proxy: makina-apache-post-inst

{% for ncfg, cfgdata in data.get('configs', {}).items() %}
{{cfg.name}}-cfg-{{ncfg}}:
  file.managed:
    - user: "{{cfgdata.get('user', 'root') }}"
    - group: "{{cfgdata.get('group', 'root') }}"
    - mode: "{{cfgdata.get('mode', '644') }}"
    {% if not data.get('no_template', False) %}
    - template: jinja
    {% endif %}
    - source: "{{cfgdata.get('template', '') }}"
    - defaults:
        cfg: "{{cfg.name}}"
    - name: "{{cfgdata.get('dest', '') }}"
    - watch:
      - mc_proxy: makina-apache-pre-conf
    - watch_in:
      - mc_proxy: makina-apache-post-conf
{% endfor %}

makina-apache-main-conf-included-modules-svn:
  mc_apache.include_module:
    - modules:
      - dav_svn
      - authz_svn
      - mpm_prefork
      - authnz_ldap
      - ldap
    - require_in:
      - mc_apache: makina-apache-main-conf
    - watch_in:
      - mc_proxy: makina-apache-pre-conf
      - mc_proxy: makina-apache-pre-restart

var-dirs-{{cfg.name}}:
  file.directory:
    - names:
      - {{cfg.data.var}}
      - {{cfg.data.doc_root}}
      - {{cfg.data.websvn_doc_root}}
    - makedirs: true
    - user: {{cfg.user}}
    - group: {{cfg.group}}
    - watch:
      - pkg: prepreq-{{cfg.name}}

{{cfg.name}}-htaccess:
  file.managed:
    - name: {{data.htaccess}}
    - source: ''
    - user: www-data
    - group: www-data
    - mode: 770
    - require:
      - file: var-dirs-{{cfg.name}}

{% for user, passwd in httpusers.items() %}
{{cfg.name}}-{{user}}-htaccess:
  webutil.user_exists:
    - name: {{user}}
    - password: {{passwd}}
    - htpasswd_file: {{data.htaccess}}
    - options: m
    - force: true
    - watch:
      - file: {{cfg.name}}-htaccess
{% endfor %}
{{cfg.name}}-websvn-dl:
  cmd.run:
    - name: |
            wget -c "http://websvn.tigris.org/files/documents/1380/49056/websvn-{{data.wsvn_ver}}.tar.gz"
            tar xzvf websvn-{{data.wsvn_ver}}.tar.gz
            rsync -azv "websvn-{{data.wsvn_ver}}/" "{{data.websvn_doc_root}}/"
    - unless: |
              set -e
              test -e "websvn-{{data.wsvn_ver}}.tar.gz"
              test -e "websvn-{{data.wsvn_ver}}/index.php"
              test -e "{{data.websvn_doc_root}}/index.php"
    - user: "{{cfg.user}}"
    - cwd: "{{cfg.project_root}}"
    - watch_in:
      - mc_proxy: makina-apache-post-inst


{% import "makina-states/services/http/apache/macros.sls" as apache with context %}
{{apache.virtualhost(data.domain,
                     data.doc_root,
                     server_aliases=data.server_aliases,
                     vhost_basename="corpussvn-"+cfg.name,
                     vh_content_source=data.svn_vhost,
                     cfg=cfg.name) }}
{{apache.virtualhost(data.websvn_domain,
                     data.websvn_doc_root,
                     vhost_basename="corpus-websvn"+cfg.name,
                     server_aliases=data.websvn_server_aliases,
                     vh_content_source=data.websvn_vhost,
                     cfg=cfg.name) }}
