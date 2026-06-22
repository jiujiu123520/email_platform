/* Web 邮件前端 */

const { createApp, ref, reactive, onMounted, watch } = Vue;
const API = '/api';

async function http(url, options = {}) {
  const r = await fetch(API + url, {
    credentials: 'include',
    headers: { 'Content-Type': 'application/json' },
    ...options,
  });
  const j = await r.json();
  if (j.code !== 0) throw new Error(j.message);
  return j.data;
}

createApp({
  setup() {
    const loggedIn = ref(false);
    const logging = ref(false);
    const loginError = ref('');
    const loginForm = reactive({ address: '', password: '' });
    const user = ref({});
    const folders = [
      { key: 'INBOX', name: '收件箱', icon: 'fa-inbox' },
      { key: 'SENT',  name: '已发送', icon: 'fa-paper-plane' },
      { key: 'DRAFTS',name: '草稿箱', icon: 'fa-file-text-o' },
      { key: 'TRASH', name: '已删除', icon: 'fa-trash' },
    ];
    const folder = ref('INBOX');
    const currentFolderName = ref('收件箱');
    const emails = ref({ list: [], total: 0 });
    const current = ref(null);

    const composer = reactive({ show: false, to: '', subject: '', body: '', sending: false });

    const selectFolder = (k) => {
      folder.value = k;
      currentFolderName.value = folders.find(f => f.key === k).name;
      current.value = null;
      loadEmails();
    };

    const loadEmails = async () => {
      const data = await http('/mailboxes/' + user.value.id + '/emails?folder=' + folder.value + '&limit=100');
      emails.value = data;
    };

    const openEmail = async (e) => {
      const data = await http('/emails/' + e.id);
      current.value = data;
      e.is_read = 1;
    };

    const deleteEmail = async (e) => {
      try { await ElementPlus.ElMessageBox.confirm('确认删除？', '提示', { type: 'warning' }); } catch (_) { return; }
      await http('/emails/' + e.id, { method: 'DELETE' });
      ElementPlus.ElMessage.success('已删除');
      current.value = null;
      loadEmails();
    };

    const compose = () => {
      composer.to = ''; composer.subject = ''; composer.body = '';
      composer.show = true;
    };

    const sendEmail = async () => {
      if (!composer.to) return ElementPlus.ElMessage.error('请输入收件人');
      composer.sending = true;
      try {
        await http('/emails/send', {
          method: 'POST',
          body: JSON.stringify({
            from_mailbox_id: user.value.id,
            to: composer.to.split(',').map(s => s.trim()).filter(Boolean),
            subject: composer.subject,
            body_text: composer.body,
          }),
        });
        ElementPlus.ElMessage.success('发送成功');
        composer.show = false;
        if (folder.value === 'SENT') loadEmails();
      } catch (e) {
        ElementPlus.ElMessage.error(e.message);
      } finally {
        composer.sending = false;
      }
    };

    const doLogin = async () => {
      logging.value = true;
      loginError.value = '';
      try {
        // 通过 SMTP 模拟登录不现实，这里通过 admin API 查询后比对
        // 简化方案：调用一个 mailbox 登录端点
        // 这里我们直接用用户后端 API，但 mailbox 用户没有 ms_users 账号，
        // 所以这里需要单独的 mailbox 登录端点
        const r = await fetch(API + '/webmail/login', {
          method: 'POST',
          credentials: 'include',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify(loginForm),
        });
        const j = await r.json();
        if (j.code !== 0) throw new Error(j.message);
        user.value = j.data.mailbox;
        loggedIn.value = true;
        loadEmails();
      } catch (e) {
        loginError.value = e.message;
      } finally {
        logging.value = false;
      }
    };

    const doLogout = async () => {
      try { await http('/webmail/logout', { method: 'POST' }); } catch (e) {}
      loggedIn.value = false;
    };

    onMounted(async () => {
      try {
        const me = await http('/webmail/me');
        user.value = me;
        loggedIn.value = true;
        loadEmails();
      } catch (e) {}
    });

    return {
      loggedIn, logging, loginError, loginForm, user,
      folders, folder, currentFolderName, emails, current,
      composer,
      selectFolder, loadEmails, openEmail, deleteEmail, compose, sendEmail,
      doLogin, doLogout,
    };
  }
}).use(ElementPlus).mount('#app');
