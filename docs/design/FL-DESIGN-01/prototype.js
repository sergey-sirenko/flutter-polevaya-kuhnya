/* Local design examples. No authentication, business API or order submission. */
(() => {
  'use strict';
  const variants = {
    white: { name: 'Белая кухня', file: '1-white-kitchen.html' },
    warm: { name: 'Тёплый обед', file: '2-warm-lunch.html' },
    standard: { name: 'Зелёный стандарт', file: '3-green-standard.html' },
  };
  const variant = document.body.dataset.variant;
  const allDays = window.MENU_SNAPSHOT.weeks.flatMap(w => w.days.map(d => ({...d, weekType:w.weekType})));
  const params = new URLSearchParams(location.search);
  let page = params.get('page') === 'menu' ? 'menu' : 'home';
  let selectedDay = allDays.find(d => d.date === '2026-10-05') || allDays[0];
  let selectedCategory = [...selectedDay.categories].sort((a,b) => a.categoryOrder-b.categoryOrder)[0].categoryId;
  const quantityByDate = new Map();
  let quantities = () => {
    if (!quantityByDate.has(selectedDay.date)) quantityByDate.set(selectedDay.date,new Map());
    return quantityByDate.get(selectedDay.date);
  };
  const app = document.querySelector('#app');
  const esc = value => String(value ?? '').replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
  const money = value => new Intl.NumberFormat('ru-RU').format(value) + ' ₽';
  const categories = () => [...selectedDay.categories].sort((a,b) => a.categoryOrder-b.categoryOrder);
  const dishes = () => categories().flatMap(c => [...c.dishes].sort((a,b) => a.menuOrder-b.menuOrder));
  const photoVersions = {};
  for (const day of allDays) for (const category of day.categories) {
    const categoryPath=category.categoryimagePath||category.categoryImagePath;
    if(categoryPath) photoVersions[categoryPath]=category.photo_version||'legacy';
    for(const dish of category.dishes) if(dish.imagePath) photoVersions[dish.imagePath]=dish.photo_version||'legacy';
  }
  const photo = path => path ? 'images/' + encodeURIComponent(path) + '.jpg?v=' + encodeURIComponent(photoVersions[path] || 'legacy') : '';
  const dateText = date => new Date(date+'T12:00:00').toLocaleDateString('ru-RU',{day:'2-digit',month:'2-digit'});
  const dayText = date => new Date(date+'T12:00:00').toLocaleDateString('ru-RU',{weekday:'short'}).replace(/^./,s => s.toUpperCase());
  const weight = d => d.servingweight || d.servingWeight || 'Н/Д';
  const categoryPhoto = c => c.categoryimagePath || c.categoryImagePath;
  const icons = {
    menu:'<path d="M4 3v7m4-7v7M6 3v18m-2-11h4M16 3v8h4V3m0 8v10"/>',
    cart:'<path d="M2 3h3l3 13h12l2-9H6M9 21h.01M19 21h.01"/>',
    calendar:'<rect x="3" y="5" width="18" height="16" rx="2"/><path d="M7 3v4m10-4v4M3 11h18"/>',
    person:'<circle cx="12" cy="7" r="4"/><path d="M4 21v-2a8 8 0 0 1 16 0v2"/>',
  };
  const icon = name => `<svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">${icons[name] || icons.menu}</svg>`;
  const image = (path, name, cls='') => path ? `<img class="${cls}" src="${photo(path)}" alt="${esc(name)}" loading="eager">` : '<span class="empty-photo">Нет фотографии</span>';
  function header() {
    return `<header class="site-header"><div class="header-inner"><a href="${variants[variant].file}" class="brand" data-page="home"><img src="logo.png" alt=""><span>Полевая кухня</span></a><nav class="main-nav" aria-label="Разделы сайта"><button data-page="menu" class="${page==='menu'?'active':''}">Меню</button><button data-info="about">О компании</button><button data-info="delivery">Доставка</button><button data-info="how">Как заказать</button><button data-info="contacts">Контакты</button></nav><a class="header-phone" href="tel:+79031285715">8-903-128-57-15</a><button class="mobile-toggle" aria-label="Открыть разделы сайта" aria-expanded="false">☰</button></div></header>`;
  }
  function controls() {
    return `<aside class="display-controls ${page==='menu'?'menu-controls':''}" aria-label="Просмотр примера"><a href="index.html">← Все три дизайна</a><span>${esc(variants[variant].name)}</span><button data-scale="1" class="${document.body.classList.contains('large-text')?'':'active'}">Текст 100%</button><button data-scale="1.6" class="${document.body.classList.contains('large-text')?'active':''}">Текст 160%</button></aside>`;
  }
  function home() {
    const featured = [dishes().find(d=>d.menuOrder===10), dishes().find(d=>d.menuOrder===1), dishes().find(d=>d.menuOrder===9), dishes().find(d=>d.menuOrder===56)].filter(Boolean);
    const hero = featured[0] || dishes()[0];
    return `${header()}<main class="home"><section class="hero"><div class="hero-copy"><p class="eyebrow">МОСКВА · ПОЛЕВАЯ КУХНЯ</p><h1>Доставка обедов <span>в офис и на предприятия</span></h1><p>Мы специализируемся на доставке вкусных обедов в офисы и на предприятия.</p><div class="hero-actions"><button class="primary" data-page="menu">Заказать обед →</button><button class="secondary" data-info="contacts">Контакты</button></div><div class="hero-note"><span><strong>Пн–Чт</strong> с 8 до 12</span><span><strong>Пт</strong> с 8 до 15</span></div></div><div class="hero-visual"><span class="hero-stamp tag"><span class="dot"></span>В меню ${dateText(selectedDay.date)}</span>${image(hero.imagePath,hero.dishName)}<div class="hero-caption"><span>${esc(hero.dishName)}</span><strong>${money(hero.price)}</strong></div></div></section><section><div class="section-head"><h2 class="section-title">Категории блюд</h2><button class="text-action" data-page="menu">Всё меню →</button></div><div class="home-categories">${categories().map(c=>`<button class="home-category" data-category="${esc(c.categoryId)}">${image(categoryPhoto(c),c.categoryName.trim())}<span>${esc(c.categoryName.trim())}</span></button>`).join('')}</div></section><section><div class="section-head"><h2 class="section-title">Блюда на ${dateText(selectedDay.date)}</h2><span class="small muted">${esc(selectedDay.dayName)}</span></div><div class="daily-grid">${featured.map(d=>`<article class="daily-card">${image(d.imagePath,d.dishName,'daily-photo')}<div><h3>${esc(d.dishName)}</h3><strong>${money(d.price)}</strong><span class="small muted">Вес: ${esc(weight(d))}</span><button class="detail-action" data-detail="${esc(d.dishId)}">Состав блюда →</button></div></article>`).join('')}</div></section><section class="features"><div><span class="feature-icon">♧</span><h3>Свежие продукты</h3><p>Используем только качественные и свежие ингредиенты</p></div><div><span class="feature-icon">↗</span><h3>Быстрая доставка</h3><p>Доставляем горячие обеды точно в срок</p></div><div><span class="feature-icon">${icon('menu')}</span><h3>Разнообразное меню</h3><p>Широкий выбор блюд на каждый день</p></div></section></main><footer class="site-footer"><span class="copyright">ООО «Полевая кухня» · Москва</span><a href="tel:+79031285715">8-903-128-57-15</a><a href="mailto:zakaz@obedmoscow.ru">zakaz@obedmoscow.ru</a><a href="https://obedmoscow.ru/" target="_blank" rel="noopener">Сайт компании ↗</a></footer>${controls()}`;
  }
  function tools() {
    const week = window.MENU_SNAPSHOT.weeks.find(w=>w.weekType===selectedDay.weekType);
    return `<div class="menu-tools"><div class="menu-tools-inner"><div class="week-tabs">${window.MENU_SNAPSHOT.weeks.map(w=>`<button data-week="${esc(w.weekType)}" class="${w.weekType===selectedDay.weekType?'active':''}" aria-pressed="${w.weekType===selectedDay.weekType}">${w.weekType==='current'?'Текущая неделя':'Следующая неделя'}</button>`).join('')}</div><div class="day-tabs" aria-label="Дни меню">${week.days.map(d=>`<button data-date="${esc(d.date)}" class="${d.date===selectedDay.date?'active':''}" aria-pressed="${d.date===selectedDay.date}">${dayText(d.date)} ${dateText(d.date)}</button>`).join('')}</div></div></div>`;
  }
  function categoryButtons(mobile=false) {
    return categories().map(c=>`<button class="${mobile?'':'category-button '}${c.categoryId===selectedCategory?'active':''}" data-category="${esc(c.categoryId)}" aria-pressed="${c.categoryId===selectedCategory}">${mobile?'':image(categoryPhoto(c), '')}<span>${esc(c.categoryName.trim())}</span>${mobile?'':`<span class="count">${c.dishes.length}</span>`}</button>`).join('');
  }
  function nutrients(d) {
    if (!d.nutrients) return '';
    const n = d.nutrients;
    return `<div class="nutrients" aria-label="Пищевая ценность">${[['Б',n.proteins,'г'],['Ж',n.fats,'г'],['У',n.carbohydrates,'г'],['Ккал',n.calories,'']].filter(x=>x[1]!=null).map(([a,b,c])=>`<span>${a}: <b>${esc(b)}${c}</b></span>`).join('')}</div>`;
  }
  function card(d) {
    const qty = quantities().get(d.dishId)||0;
    return `<article class="dish-card ${qty?'selected':''}" data-dish="${esc(d.dishId)}"><button class="dish-photo" data-detail="${esc(d.dishId)}" aria-label="Фото и состав: ${esc(d.dishName)}">${image(d.imagePath,d.dishName)}<span class="number-badge">${esc(d.menuOrder)}</span></button><div class="dish-info"><h2 class="dish-name">${esc(d.dishName)}</h2><div class="price-line"><strong>${money(d.price)}</strong><span class="dish-weight">Вес: ${esc(weight(d))}</span></div>${nutrients(d)}<button class="detail-action" data-detail="${esc(d.dishId)}">Полный состав →</button><div class="qty"><button data-qty="${esc(d.dishId)}" data-delta="-1" aria-label="Уменьшить: ${esc(d.dishName)}" ${qty?'':'disabled'}>−</button><output aria-live="polite">${qty}</output><button class="plus" data-qty="${esc(d.dishId)}" data-delta="1" aria-label="Добавить: ${esc(d.dishName)}">+</button></div></div></article>`;
  }
  function totals() {
    const selected = dishes().filter(d => (quantities().get(d.dishId)||0)>0);
    return {selected,total:selected.reduce((s,d)=>s+d.price*quantities().get(d.dishId),0),count:selected.reduce((s,d)=>s+quantities().get(d.dishId),0)};
  }
  function cart() {
    const {selected,total,count} = totals();
    return `<div class="cart-header"><h2>Корзина</h2><span>${count} ${count===1?'порция':'порций'}</span></div><div class="day-label"><strong>${esc(selectedDay.dayName)}</strong><span>${dateText(selectedDay.date)}</span></div>${selected.length?selected.map(d=>`<div class="cart-row">${image(d.imagePath,'')}<div><h3>${esc(d.dishName)}</h3><div class="cart-row-bottom"><div class="row-actions"><button data-qty="${esc(d.dishId)}" data-delta="-1" aria-label="Уменьшить: ${esc(d.dishName)}">−</button><span>${quantities().get(d.dishId)}</span><button data-qty="${esc(d.dishId)}" data-delta="1" aria-label="Добавить: ${esc(d.dishName)}">+</button></div><strong>${money(d.price*quantities().get(d.dishId))}</strong></div></div></div>`).join(''):`<div class="cart-empty">${icon('cart')}<p>Выберите блюда из меню.<br>Здесь появится ваш обед.</p></div>`}<div class="cart-total"><span>Предварительно</span><strong>${money(total)}</strong></div><p class="demo-note">Пример корзины. Количества меняются только здесь, заказ не отправляется.</p><button class="primary" data-demo="order" ${count?'':'disabled'}>Проверить состав →</button>`;
  }
  function samples() {
    return `<div class="form-example"><h3>Вход в личный кабинет</h3><label>Код клиента<input type="text" placeholder="Код клиента" autocomplete="off"></label><button class="secondary" data-demo="signin">Продолжить</button></div>${calendarSample()}<p class="notice" style="margin-top:16px">Состав можно проверить перед оформлением.</p>`;
  }
  function calendarSample() {
    const other=allDays.find(d=>d.date>selectedDay.date)||allDays.find(d=>d.date!==selectedDay.date);
    return `<div class="mini-calendar" aria-label="Образец дней"><div class="mini-day selected"><strong>${dayText(selectedDay.date)} ${dateText(selectedDay.date)}</strong><br>Выбранный день</div>${other?`<div class="mini-day"><strong>${dayText(other.date)} ${dateText(other.date)}</strong><br>Другой день</div>`:''}</div>`;
  }
  function bottom() {
    return `<nav class="mobile-bottom" aria-label="Навигация заказа"><button data-mobile="day">${icon('calendar')}<span>${dayText(selectedDay.date)} ${dateText(selectedDay.date)}</span></button><button class="active" data-page="menu">${icon('menu')}<span>Меню</span></button><button data-mobile="cart">${icon('cart')}<span>Корзина</span></button><button data-mobile="profile">${icon('person')}<span>Профиль</span></button></nav><div class="mobile-summary" aria-live="polite"></div>`;
  }
  function menu() {
    const category = categories().find(c=>c.categoryId===selectedCategory)||categories()[0];
    selectedCategory = category.categoryId;
    return `${header()}${tools()}<div class="menu-frame"><aside class="category-sidebar" aria-label="Категории"><p class="sidebar-caption">Категории блюд</p>${categoryButtons()}</aside><main class="menu-content"><div class="catalog-title"><div><h1>${esc(category.categoryName.trim())}</h1><p>${esc(selectedDay.dayName)}, ${dateText(selectedDay.date)} · ${category.dishes.length} блюд</p></div><span class="tag">Меню на день</span></div><nav class="mobile-categories" aria-label="Категории блюд">${categoryButtons(true)}</nav><div class="dish-grid">${[...category.dishes].sort((a,b)=>a.menuOrder-b.menuOrder).map(card).join('')}</div></main><aside class="cart-sidebar" aria-label="Пример личного раздела"><div class="panel-tabs"><button class="active" data-panel="cart">Корзина</button><button data-panel="orders">Заказы</button><button data-panel="profile">Профиль</button></div><div id="cart-body">${cart()}</div>${samples()}</aside></div>${bottom()}${controls()}`;
  }
  let lastFocus;
  function closeDialog() {
    const dialog = document.querySelector('.dialog-backdrop');
    dialog.hidden = true;
    document.body.classList.remove('no-scroll');
    if(lastFocus?.isConnected) lastFocus.focus();
  }
  function showDialog(title, content) {
    lastFocus = document.activeElement;
    const dialog = document.querySelector('.dialog-backdrop');
    dialog.innerHTML=`<section class="dialog-box" role="dialog" aria-modal="true" aria-labelledby="dialog-title"><h2 id="dialog-title">${esc(title)}</h2>${content}<div class="dialog-actions"><button class="secondary" data-close>Закрыть</button></div></section>`;
    dialog.hidden=false;
    document.body.classList.add('no-scroll');
    dialog.querySelector('[data-close]').focus();
  }
  function render(scroll=false) {
    document.title=variants[variant].name+' — '+(page==='home'?'главная':'меню')+' — Полевая кухня';
    app.innerHTML = page==='home'?home():menu();
    document.body.classList.toggle('menu-page',page==='menu');
    if(!document.querySelector('.dialog-backdrop')) {
      const dialog=document.createElement('div'); dialog.className='dialog-backdrop'; dialog.hidden=true; document.body.append(dialog);
    }
    updateTotals();
    if(scroll) window.scrollTo({top:0,behavior:'instant'});
  }
  function updateTotals() {
    if(page!=='menu') return;
    const t=totals();
    document.body.classList.toggle('has-cart',t.count>0);
    const box=document.querySelector('#cart-body'); if(box) box.innerHTML=cart();
    const summary=document.querySelector('.mobile-summary');
    summary.innerHTML=`<div><span class="small muted">${t.count} порций · ${dateText(selectedDay.date)}</span><br><strong>${money(t.total)}</strong></div><button class="primary" data-mobile="cart">В корзину →</button>`;
    summary.classList.toggle('visible',t.count>0);
  }
  function setPage(value) {
    page=value;
    const url=new URL(location.href);url.searchParams.set('page',page);history.replaceState({},'',url);
    render(true);
  }
  function changeDay(date) {
    const found=allDays.find(d=>d.date===date);if(!found)return;
    selectedDay=found;
    if(!categories().some(c=>c.categoryId===selectedCategory))selectedCategory=categories()[0].categoryId;
    closeDialog();render(true);
  }
  document.addEventListener('click',event=>{
    const button=event.target.closest('button,a');
    if(event.target.classList.contains('dialog-backdrop')) {closeDialog();return;}
    if(!button)return;
    if(button.hasAttribute('data-close')) {closeDialog();return;}
    if(button.dataset.page){event.preventDefault();setPage(button.dataset.page);return;}
    if(button.classList.contains('mobile-toggle')){
      const open=document.querySelector('.main-nav').classList.toggle('open');button.setAttribute('aria-expanded',String(open));return;
    }
    if(button.dataset.scale){document.body.classList.toggle('large-text',button.dataset.scale==='1.6');render();return;}
    if(button.dataset.category){selectedCategory=button.dataset.category;setPage('menu');return;}
    if(button.dataset.date){changeDay(button.dataset.date);return;}
    if(button.dataset.week){const week=window.MENU_SNAPSHOT.weeks.find(w=>w.weekType===button.dataset.week);if(week?.days.length)changeDay(week.days[0].date);return;}
    if(button.dataset.detail){const d=dishes().find(d=>d.dishId===button.dataset.detail);if(d)showDialog(d.dishName,`${image(d.imagePath,d.dishName)}<div class="price-line"><strong>${money(d.price)}</strong><span class="dish-weight">Вес: ${esc(weight(d))}</span></div>${nutrients(d)}<h3>Полный состав</h3><p>${esc(d.ingredients?.detailedDescription || d.ingredients?.textDescription || 'Состав не указан в меню.')}</p>`);return;}
    if(button.dataset.qty){
      const id=button.dataset.qty,delta=Number(button.dataset.delta),old=quantities().get(id)||0;
      quantities().set(id,Math.max(0,old+delta));
      const cardElement=document.querySelector(`[data-dish="${CSS.escape(id)}"]`);
      if(cardElement){const q=quantities().get(id);cardElement.classList.toggle('selected',q>0);cardElement.querySelector('output').textContent=q;cardElement.querySelector('[data-delta="-1"]').disabled=!q;}
      updateTotals();
      if(!document.querySelector('.dialog-backdrop').hidden && document.querySelector('#dialog-title').textContent==='Корзина')showDialog('Корзина',cart());
      return;
    }
    if(button.dataset.mobile==='cart'){showDialog('Корзина',cart());return;}
    if(button.dataset.mobile==='profile'||button.dataset.panel==='profile'){showDialog('Профиль',`<p class="muted">Образец оформления личного раздела</p>${samples()}<p class="notice warning" style="margin-top:16px">Для просмотра личных данных нужен вход. В примере вход не выполняется.</p>`);return;}
    if(button.dataset.mobile==='day'){showDialog('День меню',`<div class="day-tabs" style="flex-wrap:wrap">${allDays.map(d=>`<button class="secondary" data-date="${d.date}">${dayText(d.date)} ${dateText(d.date)}</button>`).join('')}</div>`);return;}
    if(button.dataset.panel==='orders'){showDialog('Заказы',`<p class="muted">Образец оформления календаря</p>${calendarSample()}<p class="notice">История заказов здесь не загружается.</p>`);return;}
    if(button.dataset.panel==='cart'){showDialog('Корзина',cart());return;}
    if(button.dataset.demo==='order'){showDialog('Проверка состава',`<p>Предварительная сумма: <strong>${money(totals().total)}</strong>.</p><p class="notice">Это пример дизайна. Заказ не отправляется.</p>`);return;}
    if(button.dataset.demo==='signin'){showDialog('Личный кабинет',`<p class="notice">Это образец формы. Код не отправляется, вход не выполняется.</p><p class="notice error">Пример сообщения об ошибке: проверьте введённый код клиента.</p>`);return;}
    if(button.dataset.info){const info={about:['О компании','Мы специализируемся на доставке вкусных обедов в офисы и на предприятия.'],delivery:['Доставка','Доставка осуществляется курьерами при условии заказов не менее 4 раз в неделю и сумме заказа в день не менее 1500 рублей.'],how:['Как заказать','Войдите в личный кабинет. Выберите блюда на нужные дни. Укажите число порций и проверьте корзину. Отправьте заказ — успех подтверждает ответ сервера.'],contacts:['Контакты','109382 г. Москва, ул. Нижние поля, 31с1. Пн–Чт: с 8 до 12. Пт: с 8 до 15. Сб, Вс — выходной.']}[button.dataset.info];showDialog(info[0],`<p>${esc(info[1])}</p><p class="contact-lines"><a href="tel:+79031285715">8-903-128-57-15</a><br><a href="mailto:zakaz@obedmoscow.ru">zakaz@obedmoscow.ru</a></p>`);}
  });
  document.addEventListener('keydown',event=>{
    const dialog=document.querySelector('.dialog-backdrop');if(dialog.hidden)return;
    if(event.key==='Escape'){closeDialog();return;}
    if(event.key==='Tab'){
      const focusable=[...dialog.querySelectorAll('button:not(:disabled),a,input,select')];
      const first=focusable[0],last=focusable.at(-1);
      if(event.shiftKey&&document.activeElement===first){event.preventDefault();last.focus();}
      if(!event.shiftKey&&document.activeElement===last){event.preventDefault();first.focus();}
    }
  });
  document.addEventListener('error',event=>{
    if(event.target instanceof HTMLImageElement && !event.target.src.endsWith('logo.png')){
      const image=event.target; const text=document.createElement('span');text.className='empty-photo';text.textContent='Нет фотографии';image.replaceWith(text);
    }
  },true);
  render();
})();
