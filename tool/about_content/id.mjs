// Bahasa Indonesia — terjemahan dari master en.mjs.
export default {
  code: 'id',
  hreflang: 'id',
  dir: 'ltr',
  nativeName: 'Bahasa Indonesia',
  content: {
    title: 'Tentang Aura OmniMesh — protokol barter lokal tanpa server',
    metaDescription:
      'Apa itu Aura OmniMesh, mengapa dibuat, dan cara kerjanya: protokol terbuka yang menemukan lingkaran barter multilateral antara ponsel-ponsel di sekitar — tanpa server, tanpa akun, tanpa internet.',
    kicker: 'Tentang',
    backHome: 'Beranda',
    langLabel: 'Bahasa',
    h1: 'Bertukar tanpa infrastruktur.',
    lede:
      'Aura OmniMesh adalah protokol pertukaran terbuka yang local-first. Ponsel-ponsel dalam satu ruangan saling menemukan, memublikasikan penawaran dan kebutuhan yang ditandatangani, lalu menemukan lingkaran barter tertutup — siklus di mana setiap orang memberi satu hal dan menerima satu hal. Tanpa server, tanpa akun, tanpa internet.',
    whatIs: {
      label: 'Definisi',
      h2: 'Apa itu Aura OmniMesh',
      paras: [
        'Aura OmniMesh adalah protokol sekaligus aplikasi gratis untuk pertukaran langsung antara orang-orang yang berdekatan secara fisik. Setiap perangkat memublikasikan <em>intent</em> singkat yang ditandatangani — sebuah penawaran (“saya mengajar gitar”) atau kebutuhan (“butuh bantuan pindahan”) — dan model AI kecil yang berjalan di ponsel itu sendiri mencocokkannya menjadi lingkaran tertutup berisi tiga sampai tujuh peserta.',
        'Semua yang biasanya membuat sebuah marketplace membutuhkan perusahaan — identitas, pencocokan, kepercayaan, riwayat — dikerjakan sendiri oleh perangkat, secara kriptografis. Hasilnya: jaringan pertukaran yang tetap bekerja di tempat uang, bank, atau internet tidak berfungsi.',
      ],
    },
    why: {
      label: 'Motivasi',
      h2: 'Mengapa dibuat',
      paras: [
        'Barter langsung biasanya gagal karena alasan matematis: orang yang punya apa yang Anda butuhkan jarang membutuhkan apa yang Anda punya. Para ekonom menyebutnya <em>kebetulan ganda kebutuhan</em>. Lingkaran menyelesaikannya: A mengajar B, B meminjamkan ke C, C memasok A — siklus tertutup meski tak ada pasangan yang cocok secara langsung.',
        'Alasan kedua adalah kemandirian. Semua marketplace yang ada berjalan di atas server dan akun — perusahaan yang bisa mati, menyensor iklan, menaikkan biaya, atau memanen data. OmniMesh menghapus perantara sebagai fakta arsitektur, bukan sebagai janji: memang tidak ada server yang harus dipercaya, disita, atau dimatikan.',
      ],
    },
    how: {
      label: 'Protokol',
      h2: 'Cara kerjanya',
      steps: [
        {
          t: 'Identitas adalah kunci, bukan akun.',
          d: 'Saat pertama dijalankan, perangkat membuat sepasang kunci Ed25519. Kunci privat tidak pernah meninggalkan perangkat. Tanpa pendaftaran, tanpa email, tanpa nomor telepon — kunci Anda adalah identitas Anda.',
        },
        {
          t: 'Intent adalah teks yang ditandatangani.',
          d: 'Anda memublikasikan penawaran dan kebutuhan dalam kalimat pendek. Model bahasa multibahasa di ponsel mengubah setiap kalimat menjadi vektor semantik, sehingga pencocokan bekerja lintas bahasa.',
        },
        {
          t: 'Perangkat saling bertukar log bersama.',
          d: 'Ponsel-ponsel terdekat bertukar log operasi bertanda tangan lewat Bluetooth LE, Wi-Fi Direct, atau jaringan lokal bersama. Log itu adalah CRDT: tak bergantung urutan dan tahan partisi jaringan, sehingga semua perangkat mencapai keadaan yang sama tanpa koordinator.',
        },
        {
          t: 'Semua diverifikasi, tak ada yang diasumsikan.',
          d: 'Setiap operasi diperiksa: tanda tangan, kepengarangan, aturan protokol. Tanda tangan yang sah di bawah kunci yang salah tetap ditolak — hanya pemilik intent yang bisa mengubah statusnya. Reputasi tidak pernah diterima dari jaringan; setiap perangkat menghitung ulang secara lokal dari riwayat pertukaran selesai yang ditandatangani.',
        },
        {
          t: 'Pencocok mencari siklus tertutup.',
          d: 'Perangkat menelusuri graf lokal penawaran dan kebutuhan untuk mencari lingkaran berisi 3–7 peserta. Pencariannya deterministik: data yang sama menghasilkan lingkaran yang sama di ponsel mana pun.',
        },
        {
          t: 'Lingkaran terkunci, orang bertukar, riwayat tertandatangani.',
          d: 'Setiap peserta mengunci langkahnya; ketika semua terkunci, lingkaran terkonfirmasi. Orang-orang bertemu, bertukar, dan menandai pemenuhan. Setiap tahap adalah operasi bertanda tangan — mundur di tengah jalan memutus lingkaran secara terlihat bagi semua.',
        },
      ],
    },
    solves: {
      label: 'Masalah',
      h2: 'Apa yang diselesaikan',
      items: [
        '<strong>Pertukaran saat uang lemah atau tidak ada</strong> — inflasi, kelangkaan uang tunai, komunitas tanpa bank.',
        '<strong>Marketplace tanpa biaya, akun, atau server</strong> — tak ada yang perlu dibayar, tak ada tempat mendaftar.',
        '<strong>Bekerja sepenuhnya offline</strong> — bencana, pemadaman listrik, daerah terpencil, festival, kapal, perkemahan.',
        '<strong>Privasi lewat konstruksi</strong> — tak ada yang keluar dari perangkat kecuali yang Anda publikasikan secara eksplisit ke peer terdekat.',
        '<strong>Pencocokan multilateral</strong> — siklus yang secara matematis mustahil ditutup oleh barter dua orang.',
      ],
    },
    who: {
      label: 'Untuk siapa',
      h2: 'Untuk siapa ini dibuat',
      items: [
        'Kampung, desa, dan jaringan gotong royong yang menginginkan papan pertukaran lokal tanpa operator.',
        'Coworking, kampus, konferensi, dan festival — ruang padat yang penuh keterampilan saling melengkapi.',
        'Komunitas di zona bencana atau pemadaman, di mana kemandirian dari infrastruktur adalah tujuannya.',
        'Orang-orang yang menolak menyerahkan riwayat transaksinya ke perusahaan demi layanan pencocokan.',
        'Peneliti dan pengembang sistem peer-to-peer — protokol dan kodenya terbuka di GitHub.',
      ],
    },
    principles: {
      label: 'Prinsip',
      h2: 'Prinsip desain',
      items: [
        '<strong>Local-first.</strong> Data Anda tinggal di basis data tertanam di perangkat Anda. Log bertanda tangan adalah sumber kebenaran; menghapus aplikasi berarti menghapus data.',
        '<strong>Nol pengumpulan.</strong> Tanpa analitik, tanpa telemetri, tanpa akun. Tidak ada backend perusahaan tempat mengirim apa pun.',
        '<strong>Fail-closed.</strong> Apa pun yang tak bisa diverifikasi akan ditolak — tidak pernah ditebak, tidak pernah diasumsikan.',
        '<strong>Determinisme.</strong> Semua perangkat menghitung pencocokan yang identik dari data yang identik; kebenaran tidak bergantung pada siapa yang menjalankan kode.',
        '<strong>Jujur soal batasan.</strong> Protokol mendokumentasikan apa yang tidak dilakukannya, dengan bahasa lugas, di bawah ini.',
      ],
    },
    limits: {
      label: 'Batasan',
      h2: 'Ini bukan',
      items: [
        'Bukan sistem pembayaran: tanpa token, tanpa saldo, tanpa kustodi. Versi 1 adalah barter murni barang, jasa, dan waktu.',
        'Bukan jaringan global: jangkauan dibatasi radio dan jaringan lokal. Ini jaringan skala lingkungan — memang dirancang begitu.',
        'Tidak kebal Sybil: siapa pun bisa membuat kunci. Reputasi diperoleh dari lingkaran yang selesai, tidak pernah diberikan begitu saja.',
        'iOS dan Android tidak terhubung langsung lewat radio (API platform berbeda); lalu lintas lintas-OS melewati jembatan jaringan lokal.',
      ],
    },
    faq: {
      h2: 'Pertanyaan umum',
      items: [
        {
          q: 'Apakah gratis?',
          a: 'Ya — gratis dan open source, tanpa iklan dan tak ada yang dijual. Tidak ada server yang harus dibiayai, jadi tidak ada yang perlu dimonetisasi.',
        },
        {
          q: 'Bahasa apa saja yang dipahami pencocokan?',
          a: 'Model di perangkat bersifat multibahasa: penawaran yang ditulis dalam satu bahasa bisa cocok dengan kebutuhan dalam bahasa lain. Saat ini bahasa Inggris dan Rusia sudah tervalidasi; keluarga modelnya mencakup puluhan bahasa.',
        },
        {
          q: 'Bisakah saya membangun hal lain di atas protokol ini?',
          a: 'Bisa. Lapisan-lapisannya — transport, log CRDT bertanda tangan, pencocok semantik — dapat dipisah, dan kode sumbernya publik di GitHub, di repositori proyek.',
        },
      ],
    },
    footerTag: 'AURA OMNIMESH — protokol pertukaran local-first. Nol server sejak dirancang.',
  },
};
