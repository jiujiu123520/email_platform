/* MailSystem Admin UI */

const { createApp, ref, reactive, computed, onMounted, watch } = Vue;

const API_BASE = '/api';

// HTTP 请求封装
async function http(url, options = {}) {
  const resp = await fetch(API_BASE + url, {
    credentials: 'include',
    headers: {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      ...(options.headers || {}),
    },
    ...options,
  });
  if (resp.status === 401) {
    location.reload();
    throw new Error('未登录');
  }
  const json = await resp.json();
  if (json.code !== 0) {
    throw new Error(json.message || '请求失败');
  }
  return json.data;
}

const app = createApp({
  setup() {
    // === 状态 ===
    const loggedIn = ref(false);
    const logging  = ref(false);
    const loginError = ref('');
    const loginForm = reactive({ username: '', password: '' });
    const user = ref({});
    const page = ref('dashboard');
    const pageTitle = computed(() => ({
      dashboard: '仪表盘',
      domains:   '域名管理',
      mailboxes: '邮箱管理',
      emails:    '邮件记录',
      ports:     '端口管理',
      services:  '服务状态',
      apikeys:   'API 密钥',
      users:     '用户管理',
      settings:  '系统设置',
      logs:      '操作日志',
      info:      '系统信息',
    })[page.value] || 'MailSystem');

    // 仪表盘
    const stats = ref({});
    const services = ref([]);
    const statsCards = computed(() => [
      { label: '用户', value: stats.value.users || 0,    icon: 'fa-users' },
      { label: '域名', value: stats.value.domains || 0,  icon: 'fa-globe' },
      { label: '邮箱', value: stats.value.mailboxes|| 0, icon: 'fa-inbox' },
      { label: '邮件', value: stats.value.emains || stats.value.emails || 0, icon: 'fa-envelope' },
      { label: '未读', value: stats.value.unread || 0,   icon: 'fa-envelope-open' },
      { label: 'API 密钥', value: stats.value.api_keys || 0, icon: 'fa-key' },
    ]);

    // 域名
    const domains = ref([]);
    const showDomainDialog = (d) => {
      const isEdit = !!d;
      const id = d ? d.id : 0;
      const domain = d ? d.domain : '';
      const description = d ? (d.description || '') : '';
      const status = d ? d.status : 1;
      dialog.show = true;
      dialog.title = isEdit ? '编辑域名' : '添加域名';
      dialog.body = `
        <div style="margin-bottom:12px;"><label style="display:block; margin-bottom:4px; font-size:13px;">域名</label>
          <input id="d-domain" value="${domain}" class="btn" style="width:100%; text-align:left; padding:6px 10px;" placeholder="example.com" ${isEdit?'readonly':''}></div>
        <div style="margin-bottom:12px;"><label style="display:block; margin-bottom:4px; font-size:13px;">说明</label>
          <input id="d-desc" value="${description}" class="btn" style="width:100%; text-align:left; padding:6px 10px;"></div>
        ${isEdit ? `<div style="margin-bottom:12px;"><label style="display:block; margin-bottom:4px; font-size:13px;">状态</label>
          <select id="d-status" class="btn" style="width:100%; padding:6px 10px;">
            <option value="1" ${status==1?'selected':''}>启用</option>
            <option value="0" ${status==0?'selected':''}>禁用</option>
          </select></div>` : ''}
      `;
      dialog.onOk = async () => {
        const payload = { description: document.getElementById('d-desc').value };
        if (isEdit) {
          payload.status = parseInt(document.getElementById('d-status').value);
          await http('/domains/' + id, { method: 'PUT', body: JSON.stringify(payload) });
        } else {
          payload.domain = document.getElementById('d-domain').value;
          await http('/domains', { method: 'POST', body: JSON.stringify(payload) });
        }
        dialog.show = false;
        loadDomains();
        ElMessage.success('操作成功');
      };
    };
    const showDomainDns = async (d) => {
      const data = await http('/domains/' + d.id + '/dns');
      dialog.show = true;
      dialog.title = `${d.domain} - DNS 记录配置`;
      dialog.body = `
        <p style="color:#666; font-size:13px; margin-bottom:12px;">请在你的域名 DNS 服务商处添加以下记录：</p>
        <table class="dns-table" style="width:100%; border-collapse:collapse;">
          <thead><tr style="background:#fafafa;"><th style="padding:8px;">类型</th><th style="padding:8px;">主机记录</th><th style="padding:8px;">值</th><th style="padding:8px;">优先级</th></tr></thead>
          <tbody>
            ${data.records.map(r => `<tr>
              <td style="padding:8px; border-bottom:1px solid #f0f0f0;"><strong>${r.type}</strong></td>
              <td style="padding:8px; border-bottom:1px solid #f0f0f0;"><code>${r.host}</code></td>
              <td style="padding:8px; border-bottom:1px solid #f0f0f0;"><code>${r.value}</code></td>
              <td style="padding:8px; border-bottom:1px solid #f0f0f0;">${r.priority || '-'}</td>
            </tr>`).join('')}
          </tbody>
        </table>
      `;
      dialog.onOk = () => { dialog.show = false; };
    };
    const deleteDomain = async (d) => {
      try { await ElMessageBox.confirm('确认删除域名 ' + d.domain + '？', '提示', { type: 'warning' }); } catch (e) { return; }
      await http('/domains/' + d.id, { method: 'DELETE' });
      ElMessage.success('已删除');
      loadDomains();
    };
    const loadDomains = async () => { domains.value = (await http('/domains')).list; };

    // 邮箱
    const mailboxes = ref([]);
    const showMailboxDialog = (m) => {
      const isEdit = !!m;
      dialog.show = true;
      dialog.title = isEdit ? '编辑邮箱' : '创建邮箱';
      let domSelect = '';
      if (!isEdit) {
        domSelect = `<option value="">请选择域名</option>` + domains.value.map(d => `<option value="${d.id}">${d.domain}</option>`).join('');
      }
      dialog.body = `
        ${!isEdit ? `<div style="margin-bottom:12px;"><label style="display:block; margin-bottom:4px; font-size:13px;">域名</label>
          <select id="mb-domain" class="btn" style="width:100%; padding:6px 10px;">${domSelect}</select></div>
        <div style="margin-bottom:12px;"><label style="display:block; margin-bottom:4px; font-size:13px;">邮箱前缀</label>
          <input id="mb-local" class="btn" style="width:100%; text-align:left; padding:6px 10px;" placeholder="user"></div>` : ''}
        <div style="margin-bottom:12px;"><label style="display:block; margin-bottom:4px; font-size:13px;">显示名</label>
          <input id="mb-name" value="${m?(m.display_name||''):''}" class="btn" style="width:100%; text-align:left; padding:6px 10px;"></div>
        <div style="margin-bottom:12px;"><label style="display:block; margin-bottom:4px; font-size:13px;">${isEdit?'重置密码（留空不修改）':'密码'} (至少 6 位)</label>
          <input id="mb-pass" type="password" class="btn" style="width:100%; text-align:left; padding:6px 10px;"></div>
        <div style="margin-bottom:12px;"><label style="display:block; margin-bottom:4px; font-size:13px;">配额 (MB)</label>
          <input id="mb-quota" type="number" value="${m?m.quota_mb:1024}" class="btn" style="width:100%; text-align:left; padding:6px 10px;"></div>
      `;
      dialog.onOk = async () => {
        if (isEdit) {
          const payload = {
            display_name: document.getElementById('mb-name').value,
            quota_mb: parseInt(document.getElementById('mb-quota').value),
          };
          const pwd = document.getElementById('mb-pass').value;
          if (pwd) payload.password = pwd;
          await http('/mailboxes/' + m.id, { method: 'PUT', body: JSON.stringify(payload) });
        } else {
          const payload = {
            domain_id: parseInt(document.getElementById('mb-domain').value),
            local_part: document.getElementById('mb-local').value,
            display_name: document.getElementById('mb-name').value,
            password: document.getElementById('mb-pass').value,
            quota_mb: parseInt(document.getElementById('mb-quota').value),
          };
          if (!payload.domain_id) return ElMessage.error('请选择域名');
          if (!payload.local_part) return ElMessage.error('请输入邮箱前缀');
          if (!payload.password || payload.password.length < 6) return ElMessage.error('密码至少 6 位');
          await http('/mailboxes', { method: 'POST', body: JSON.stringify(payload) });
        }
        dialog.show = false;
        loadMailboxes();
        ElMessage.success('操作成功');
      };
    };
    const deleteMailbox = async (m) => {
      try { await ElMessageBox.confirm('确认删除 ' + m.full_address + '？此操作将清除所有邮件', '提示', { type: 'warning' }); } catch (e) { return; }
      await http('/mailboxes/' + m.id, { method: 'DELETE' });
      ElMessage.success('已删除');
      loadMailboxes();
    };
    const loadMailboxes = async () => { mailboxes.value = (await http('/mailboxes')).list; };

    // 邮件
    const emails = ref({ list: [], total: 0 });
    const emailFilter = reactive({ mailboxId: '', folder: 'INBOX' });
    const emailDetail = reactive({ show: false, data: {} });
    const loadEmails = async () => {
      if (!emailFilter.mailboxId) { emails.value = { list: [], total: 0 }; return; }
      const data = await http('/mailboxes/' + emailFilter.mailboxId + '/emails?folder=' + emailFilter.folder + '&limit=50');
      emails.value = data;
    };
    const showEmail = async (e) => {
      const data = await http('/emails/' + e.id);
      emailDetail.data = data;
      emailDetail.show = true;
      e.is_read = 1;
    };
    watch([() => emailFilter.mailboxId, () => emailFilter.folder], loadEmails);

    // 端口
    const ports = ref([]);
    const portStatus = ref({});
    const showPortDialog = () => {
      dialog.show = true;
      dialog.title = '添加端口';
      dialog.body = `
        <div style="margin-bottom:12px;"><label style="display:block; margin-bottom:4px; font-size:13px;">服务类型</label>
          <select id="p-svc" class="btn" style="width:100%; padding:6px 10px;">
            <option value="smtp">SMTP (发送)</option>
            <option value="pop3">POP3 (接收下载)</option>
            <option value="imap">IMAP (接收同步)</option>
          </select></div>
        <div style="margin-bottom:12px;"><label style="display:block; margin-bottom:4px; font-size:13px;">端口号</label>
          <input id="p-port" type="number" class="btn" style="width:100%; text-align:left; padding:6px 10px;" placeholder="例如 25/465/587/110/995/143/993"></div>
        <div style="margin-bottom:12px;"><label style="display:block; margin-bottom:4px; font-size:13px;">加密方式</label>
          <select id="p-ssl" class="btn" style="width:100%; padding:6px 10px;">
            <option value="0">明文 (无加密)</option>
            <option value="1">SSL (端口必须为 465/995/993)</option>
            <option value="2">STARTTLS (推荐 587/143)</option>
          </select></div>
        <div style="margin-bottom:12px;"><label style="display:block; margin-bottom:4px; font-size:13px;">绑定 IP</label>
          <input id="p-bind" class="btn" style="width:100%; text-align:left; padding:6px 10px;" value="0.0.0.0"></div>
        <div style="margin-bottom:12px;"><label style="display:block; margin-bottom:4px; font-size:13px;">说明</label>
          <input id="p-desc" class="btn" style="width:100%; text-align:left; padding:6px 10px;"></div>
      `;
      dialog.onOk = async () => {
        const sslMode = document.getElementById('p-ssl').value;
        const payload = {
          service: document.getElementById('p-svc').value,
          port: parseInt(document.getElementById('p-port').value),
          ssl: sslMode === '1' ? 1 : 0,
          tls: sslMode === '2' ? 1 : 0,
          bind_ip: document.getElementById('p-bind').value,
          description: document.getElementById('p-desc').value,
        };
        if (!payload.port) return ElMessage.error('请输入端口');
        try {
          await http('/ports', { method: 'POST', body: JSON.stringify(payload) });
        } catch (e) {
          return ElMessage.error(e.message);
        }
        dialog.show = false;
        loadPorts();
        ElMessage.success('已添加');
      };
    };
    const togglePort = async (p) => {
      await http('/ports/' + p.id, { method: 'PUT', body: JSON.stringify({ enabled: p.enabled==1?0:1 }) });
      loadPorts();
    };
    const deletePort = async (p) => {
      try { await ElMessageBox.confirm('确认删除端口 ' + p.port + '？', '提示', { type: 'warning' }); } catch (e) { return; }
      await http('/ports/' + p.id, { method: 'DELETE' });
      loadPorts();
    };
    const testPort = async (p) => {
      try {
        const data = await http('/ports/' + p.id + '/test', { method: 'POST', body: '{}' });
        if (data.success) {
          ElMessage.success('端口正常 - ' + data.banner);
        } else {
          ElMessage.error(data.message);
        }
      } catch (e) { ElMessage.error(e.message); }
    };
    const loadPorts = async () => { ports.value = (await http('/ports')).list; };
    const loadServices = async () => {
      const data = await http('/system/services');
      services.value = data.list;
      data.list.forEach(s => portStatus.value[s.id] = s.running);
    };

    // API Key
    const apiKeys = ref([]);
    const apiKeyDialog = reactive({ show: false, accessKey: '', secretKey: '' });
    const showApiKeyDialog = () => {
      dialog.show = true;
      dialog.title = '创建 API 密钥';
      dialog.body = `
        <div style="margin-bottom:12px;"><label style="display:block; margin-bottom:4px; font-size:13px;">名称</label>
          <input id="k-name" class="btn" style="width:100%; text-align:left; padding:6px 10px;" placeholder="例如: 我的应用"></div>
        <div style="margin-bottom:12px;"><label style="display:block; margin-bottom:4px; font-size:13px;">权限 (逗号分隔)</label>
          <input id="k-perms" class="btn" style="width:100%; text-align:left; padding:6px 10px;" value="read,send"></div>
      `;
      dialog.onOk = async () => {
        const name = document.getElementById('k-name').value;
        if (!name) return ElMessage.error('请输入名称');
        const perms = document.getElementById('k-perms').value;
        const data = await http('/api-keys', { method: 'POST', body: JSON.stringify({ name, permissions: perms }) });
        dialog.show = false;
        apiKeyDialog.accessKey = data.access_key;
        apiKeyDialog.secretKey = data.secret_key;
        apiKeyDialog.show = true;
        loadApiKeys();
      };
    };
    const deleteApiKey = async (k) => {
      try { await ElMessageBox.confirm('确认删除该 API Key？', '提示', { type: 'warning' }); } catch (e) { return; }
      await http('/api-keys/' + k.id, { method: 'DELETE' });
      loadApiKeys();
    };
    const loadApiKeys = async () => { apiKeys.value = (await http('/api-keys')).list; };

    // 用户
    const users = ref([]);
    const showUserDialog = (u) => {
      const isEdit = !!u;
      dialog.show = true;
      dialog.title = isEdit ? '编辑用户' : '添加用户';
      dialog.body = `
        ${!isEdit ? `<div style="margin-bottom:12px;"><label style="display:block; margin-bottom:4px; font-size:13px;">用户名</label>
          <input id="u-name" class="btn" style="width:100%; text-align:left; padding:6px 10px;"></div>` : ''}
        <div style="margin-bottom:12px;"><label style="display:block; margin-bottom:4px; font-size:13px;">邮箱</label>
          <input id="u-email" value="${u?(u.email||''):''}" class="btn" style="width:100%; text-align:left; padding:6px 10px;"></div>
        <div style="margin-bottom:12px;"><label style="display:block; margin-bottom:4px; font-size:13px;">${isEdit?'重置密码（留空不修改）':'密码'}</label>
          <input id="u-pass" type="password" class="btn" style="width:100%; text-align:left; padding:6px 10px;"></div>
        <div style="margin-bottom:12px;"><label style="display:block; margin-bottom:4px; font-size:13px;">角色</label>
          <select id="u-role" class="btn" style="width:100%; padding:6px 10px;">
            <option value="user" ${u&&u.role==='user'?'selected':''}>普通用户</option>
            <option value="admin" ${u&&u.role==='admin'?'selected':''}>管理员</option>
          </select></div>
      `;
      dialog.onOk = async () => {
        if (isEdit) {
          const payload = {
            email: document.getElementById('u-email').value,
            role: document.getElementById('u-role').value,
          };
          const pwd = document.getElementById('u-pass').value;
          if (pwd) payload.password = pwd;
          await http('/users/' + u.id, { method: 'PUT', body: JSON.stringify(payload) });
        } else {
          await http('/users', { method: 'POST', body: JSON.stringify({
            username: document.getElementById('u-name').value,
            email: document.getElementById('u-email').value,
            password: document.getElementById('u-pass').value,
            role: document.getElementById('u-role').value,
          }) });
        }
        dialog.show = false;
        loadUsers();
        ElMessage.success('操作成功');
      };
    };
    const deleteUser = async (u) => {
      try { await ElMessageBox.confirm('确认删除用户 ' + u.username + '？', '提示', { type: 'warning' }); } catch (e) { return; }
      await http('/users/' + u.id, { method: 'DELETE' });
      loadUsers();
    };
    const loadUsers = async () => { users.value = (await http('/users')).list; };

    // 设置
    const settings = reactive({});
    const settingGroups = ref([]);
    const loadSettings = async () => {
      const data = await http('/settings');
      const all = data.list;
      const groups = {};
      all.forEach(s => {
        settings[s.key_name] = s.value;
        if (!groups[s.group_name]) groups[s.group_name] = [];
        groups[s.group_name].push(s);
      });
      const labels = { general: '通用', security: '安全', mail: '邮件', api: 'API' };
      settingGroups.value = Object.keys(groups).map(g => ({
        name: g,
        label: labels[g] || g,
        items: groups[g],
      }));
    };
    const saveSettings = async () => {
      const payload = { settings };
      await http('/settings', { method: 'POST', body: JSON.stringify(payload) });
      ElMessage.success('设置已保存');
    };

    // 日志
    const logs = ref([]);
    const loadLogs = async () => { logs.value = (await http('/logs?limit=100')).list; };

    // 系统信息
    const sysInfo = ref({});
    const loadSystemInfo = async () => { sysInfo.value = await http('/system/info'); };

    // 通用
    const dialog = reactive({ show: false, title: '', body: '', onOk: null });
    const stats_loaded = ref(false);

    const doLogin = async () => {
      logging.value = true;
      loginError.value = '';
      try {
        const data = await http('/auth/login', {
          method: 'POST',
          body: JSON.stringify(loginForm),
        });
        user.value = data.user;
        loggedIn.value = true;
        localStorage.setItem('ms_user', JSON.stringify(data.user));
        await loadAll();
      } catch (e) {
        loginError.value = e.message;
      } finally {
        logging.value = false;
      }
    };
    const doLogout = async () => {
      try { await http('/auth/logout', { method: 'POST' }); } catch (e) {}
      loggedIn.value = false;
      localStorage.removeItem('ms_user');
    };
    const loadAll = async () => {
      try {
        stats.value = await http('/system/stats');
        services.value = (await http('/system/services')).list;
        services.value.forEach(s => portStatus.value[s.id] = s.running);
        await loadDomains();
        await loadMailboxes();
        await loadPorts();
        await loadApiKeys();
        if (user.value.role === 'admin') {
          await loadUsers();
          await loadSettings();
          await loadLogs();
          await loadSystemInfo();
        }
      } catch (e) {
        console.error(e);
      }
    };

    // 自动登录检查
    onMounted(async () => {
      try {
        const data = await http('/auth/me');
        user.value = data;
        loggedIn.value = true;
        await loadAll();
      } catch (e) {
        loggedIn.value = false;
      }
    });

    // 路由切换时加载数据
    watch(page, async (p) => {
      if (!loggedIn.value) return;
      if (p === 'settings' && user.value.role === 'admin') await loadSettings();
      if (p === 'logs' && user.value.role === 'admin') await loadLogs();
      if (p === 'info') await loadSystemInfo();
      if (p === 'services') await loadServices();
      if (p === 'ports') { await loadPorts(); await loadServices(); }
    });

    return {
      loggedIn, logging, loginError, loginForm, user, page, pageTitle,
      stats, statsCards, services,
      domains, showDomainDialog, showDomainDns, deleteDomain,
      mailboxes, showMailboxDialog, deleteMailbox,
      emails, emailFilter, emailDetail, showEmail,
      ports, portStatus, showPortDialog, togglePort, deletePort, testPort,
      apiKeys, apiKeyDialog, showApiKeyDialog, deleteApiKey,
      users, showUserDialog, deleteUser,
      settings, settingGroups, saveSettings,
      logs,
      sysInfo,
      dialog,
      doLogin, doLogout,
    };
  }
});

app.use(ElementPlus, { locale: ElementPlusLocaleZhCn });
app.mount('#app');
