const app = document.getElementById('app');
const closeBtn = document.getElementById('close');
const title = document.getElementById('title');

const pumpBox = document.getElementById('pumpBox');
const refineryBox = document.getElementById('refineryBox');
const drumBox = document.getElementById('drumBox');

const btnPump = document.getElementById('btnPump');
const btnRefine = document.getElementById('btnRefine');
const btnPour = document.getElementById('btnPour');
const btnFill = document.getElementById('btnFill');

const refIn = document.getElementById('refIn');
const refOut = document.getElementById('refOut');

const drumLevelText = document.getElementById('drumLevelText');
const drumLevelNumbers = document.getElementById('drumLevelNumbers');
const drumDrain = document.getElementById('drumDrain');
const drumAdd = document.getElementById('drumAdd');
const drumBar = document.getElementById('drumBar');

app.classList.add('hidden');

const RES = (typeof GetParentResourceName === 'function' && GetParentResourceName()) || 'SiiK-H-fuel-refining';

function post(name, data={}) {
  fetch(`https://${RES}/${name}`, {
    method:'POST',
    headers:{'Content-Type':'application/json'},
    body: JSON.stringify(data)
  }).catch(() => {});
}

function show(which){
  pumpBox.classList.add('hidden');
  refineryBox.classList.add('hidden');
  drumBox.classList.add('hidden');
  if(which === 'pump') pumpBox.classList.remove('hidden');
  if(which === 'refinery') refineryBox.classList.remove('hidden');
  if(which === 'drum') drumBox.classList.remove('hidden');
}

function setDrumBar(level, max){
  const lvl = Number(level || 0);
  const mx  = Number(max || 0);
  const pct = mx > 0 ? Math.round((lvl / mx) * 100) : 0;

  drumLevelText.textContent = `${pct}%`;
  drumLevelNumbers.textContent = `${Math.round(lvl)} / ${Math.round(mx)}`;
  drumBar.style.width = `${pct}%`;
}

window.addEventListener('message', (e) => {
  const { action, payload } = e.data || {};

  if(action === 'open'){
    app.classList.remove('hidden');
    title.textContent = payload?.title || 'CONSOLE';

    if(payload?.ui === 'pump'){
      show('pump');
    } else if(payload?.ui === 'refinery'){
      show('refinery');
      refIn.textContent = `${payload?.crudeRequired || 0} CRUDE OIL`;
      refOut.textContent = `${payload?.refinedOut || 0} REFINED FUEL`;
    } else if(payload?.ui === 'drum'){
      show('drum');
      drumDrain.textContent = `Drain: ${payload?.drain || 0}`;
      drumAdd.textContent = `Pour: ${payload?.add || 0}`;
      setDrumBar(payload?.level, payload?.max);
    }
  }

  if(action === 'drumLiveUpdate'){
    setDrumBar(payload?.level, payload?.max);
  }

  if(action === 'close'){
    app.classList.add('hidden');
  }
});

closeBtn.addEventListener('click', () => post('close'));
btnPump.addEventListener('click', () => post('pump'));
btnRefine.addEventListener('click', () => post('refine'));
btnPour.addEventListener('click', () => post('drum_pour'));
btnFill.addEventListener('click', () => post('drum_fill'));

document.addEventListener('keydown', (e) => {
  if(e.key === 'Escape') post('close');
});
