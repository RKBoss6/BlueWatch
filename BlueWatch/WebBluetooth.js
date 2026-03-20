/**
 * WebBluetooth.js — injected by Swift at atDocumentStart
 *
 * Swift calls back via:
 *   window.__bluetoothCallback(id, errorOrNull, resultOrNull)
 *   window.__bluetoothNotify(charId, [byte,...])
 *   window.__bluetoothDisconnected()
 *   window.__bluetoothResetSession()   ← called by Swift on each requestDevice
 */
(function () {
  'use strict';

  // ── Promise bridge ──────────────────────────────────────────────────────────
  var _pending = {};
  var _nextId  = 0;

  function _call(method, args) {
    return new Promise(function (resolve, reject) {
      var id = ++_nextId;
      _pending[id] = { resolve: resolve, reject: reject };
      window.webkit.messageHandlers.bluetooth.postMessage({
        id: id, method: method, args: args || {}
      });
    });
  }

  window.__bluetoothCallback = function (id, error, result) {
    var p = _pending[id];
    if (!p) return;
    delete _pending[id];
    if (error) p.reject(new Error(String(error)));
    else       p.resolve(result);
  };

  // ── Notification state — reset on each new session ─────────────────────────
  var _charListeners = {};  // charId → [fn, ...]
  var _charObjects   = {};  // charId → characteristic proxy
  var _charBuffer    = {};  // charId → [event, ...] buffered before addEventListener

  // Called by Swift at the start of every requestDevice call.
  // Clears ALL per-session state so stale listeners from the previous session
  // don't accumulate — which would cause each notification to fire N times,
  // doubling (or tripling) the data the app loader receives and corrupting JSON.
  window.__bluetoothResetSession = function () {
    console.log('[WB] session reset — clearing listeners, objects, buffers');
    _charListeners = {};
    _charObjects   = {};
    _charBuffer    = {};
  };

  window.__bluetoothNotify = function (charId, byteArray) {
    var buf  = new Uint8Array(byteArray).buffer;
    var view = new DataView(buf);

    var char = _charObjects[charId];
    if (char) char.value = view;

    var target = char || (function () {
      var t = { value: view };
      hidden(t, 'service', { device: {} });
      return t;
    }());

    var ev = { type: 'characteristicvaluechanged', bubbles: false };
    hidden(ev, 'target',        target);
    hidden(ev, 'currentTarget', target);

    var list = _charListeners[charId];
    if (!list || list.length === 0) {
      if (!_charBuffer[charId]) _charBuffer[charId] = [];
      if (_charBuffer[charId].length < 128) _charBuffer[charId].push(ev);
      return;
    }
    for (var i = 0; i < list.length; i++) {
      try { list[i](ev); } catch (e) { console.error('[WB] listener error', e); }
    }
  };

  // ── Disconnect dispatch ─────────────────────────────────────────────────────
  var _deviceListeners = {};
  window.__bluetoothDisconnected = function () {
    var ev = { type: 'gattserverdisconnected' };
    Object.keys(_deviceListeners).forEach(function (did) {
      (_deviceListeners[did] || []).forEach(function (fn) { try { fn(ev); } catch (e) {} });
    });
  };

  // ── Non-enumerable helper (breaks JSON.stringify cycles) ───────────────────
  function hidden(obj, key, value) {
    Object.defineProperty(obj, key, {
      value: value, writable: true, enumerable: false, configurable: true
    });
  }

  // ── Property decoder ────────────────────────────────────────────────────────
  function decodeProps(raw) {
    return {
      broadcast:                 !!(raw & 0x001),
      read:                      !!(raw & 0x002),
      writeWithoutResponse:      !!(raw & 0x004),
      write:                     !!(raw & 0x008),
      notify:                    !!(raw & 0x010),
      indicate:                  !!(raw & 0x020),
      authenticatedSignedWrites: !!(raw & 0x040),
      reliableWrite:             !!(raw & 0x100),
      writableAuxiliaries:       !!(raw & 0x200)
    };
  }

  // ── Object factories ────────────────────────────────────────────────────────

  function makeCharacteristic(charId, uuid, propsRaw, serviceRef) {
    var char = {
      uuid:       uuid,
      value:      null,
      properties: decodeProps(propsRaw || 0)
    };
    hidden(char, 'service', serviceRef || null);

    char.addEventListener = function (type, fn) {
      if (type !== 'characteristicvaluechanged') return;
      if (!_charListeners[charId]) _charListeners[charId] = [];
      _charListeners[charId].push(fn);

      var buffered = _charBuffer[charId];
      if (buffered && buffered.length > 0) {
        var toFlush = buffered.splice(0);
        for (var i = 0; i < toFlush.length; i++) {
          hidden(toFlush[i], 'target',        char);
          hidden(toFlush[i], 'currentTarget', char);
        }
        setTimeout(function () {
          for (var i = 0; i < toFlush.length; i++) {
            try { fn(toFlush[i]); } catch (e) { console.error('[WB] flush error', e); }
          }
        }, 0);
      }
    };

    char.removeEventListener = function (type, fn) {
      if (!_charListeners[charId]) return;
      _charListeners[charId] = _charListeners[charId].filter(function (f) { return f !== fn; });
    };

    char.startNotifications        = function () { return _call('startNotifications',  { charId: charId }); };
    char.stopNotifications         = function () { return _call('stopNotifications',   { charId: charId }); };
    char.writeValue                = function (b) { return _call('writeValue', { charId: charId, value: Array.from(new Uint8Array(b)) }); };
    char.writeValueWithResponse    = function (b) { return char.writeValue(b); };
    char.writeValueWithoutResponse = function (b) { return char.writeValue(b); };

    char.readValue = function () {
      return _call('readValue', { charId: charId }).then(function (arr) {
        var view = new DataView(new Uint8Array(arr).buffer);
        char.value = view;
        return view;
      });
    };

    _charObjects[charId] = char;
    return char;
  }

  function makeService(serviceId, uuid, deviceRef) {
    var service = { uuid: uuid };
    hidden(service, 'device', deviceRef);

    service.getCharacteristic = function (charUUID) {
      var full = resolveUUID(charUUID);
      return _call('getCharacteristic', { serviceId: serviceId, charUUID: full })
        .then(function (r) { return makeCharacteristic(r.charId, full, r.props, service); });
    };
    service.getCharacteristics = function (charUUID) {
      return service.getCharacteristic(charUUID).then(function (c) { return [c]; });
    };
    return service;
  }

  function makeGATTServer(deviceId, deviceRef) {
    var server = { connected: false };
    hidden(server, 'device', deviceRef);

    server.connect = function () {
      return _call('gattConnect', { deviceId: deviceId }).then(function () {
        server.connected = true; return server;
      });
    };
    server.disconnect = function () {
      server.connected = false;
      return _call('gattDisconnect', { deviceId: deviceId });
    };
    server.getPrimaryService = function (serviceUUID) {
      var full = resolveUUID(serviceUUID);
      return _call('getPrimaryService', { deviceId: deviceId, serviceUUID: full })
        .then(function (r) { return makeService(r.serviceId, full, deviceRef); });
    };
    server.getPrimaryServices = function (serviceUUID) {
      return server.getPrimaryService(serviceUUID).then(function (s) { return [s]; });
    };
    return server;
  }

  function makeDevice(deviceId, name) {
    var device = { id: deviceId, name: name };
    var gatt = makeGATTServer(deviceId, device);
    hidden(device, 'gatt', gatt);

    device.addEventListener = function (type, fn) {
      if (!_deviceListeners[deviceId]) _deviceListeners[deviceId] = [];
      _deviceListeners[deviceId].push(fn);
    };
    device.removeEventListener = function (type, fn) {
      if (!_deviceListeners[deviceId]) return;
      _deviceListeners[deviceId] = _deviceListeners[deviceId].filter(function (f) { return f !== fn; });
    };
    return device;
  }

  // ── UUID resolver ───────────────────────────────────────────────────────────
  var _uuidAliases = {
    'generic_access':            '00001800-0000-1000-8000-00805f9b34fb',
    'generic_attribute':         '00001801-0000-1000-8000-00805f9b34fb',
    'battery_service':           '0000180f-0000-1000-8000-00805f9b34fb',
    'cycling_power':             '00001818-0000-1000-8000-00805f9b34fb',
    'cycling_speed_and_cadence': '00001816-0000-1000-8000-00805f9b34fb',
    'device_information':        '0000180a-0000-1000-8000-00805f9b34fb',
    'environmental_sensing':     '0000181a-0000-1000-8000-00805f9b34fb',
    'heart_rate':                '0000180d-0000-1000-8000-00805f9b34fb',
    'running_speed_and_cadence': '00001814-0000-1000-8000-00805f9b34fb',
    'weight_scale':              '0000181d-0000-1000-8000-00805f9b34fb',
    'battery_level':             '00002a19-0000-1000-8000-00805f9b34fb',
    'heart_rate_measurement':    '00002a37-0000-1000-8000-00805f9b34fb',
    'manufacturer_name_string':  '00002a29-0000-1000-8000-00805f9b34fb',
    'model_number_string':       '00002a24-0000-1000-8000-00805f9b34fb'
  };

  function resolveUUID(uuid) {
    if (!uuid) return uuid;
    if (typeof uuid === 'string' && uuid.indexOf('-') !== -1) return uuid.toLowerCase();
    if (typeof uuid === 'number') {
      return '0000' + uuid.toString(16).padStart(4, '0') + '-0000-1000-8000-00805f9b34fb';
    }
    if (typeof uuid === 'string') {
      var n = parseInt(uuid, 16);
      if (!isNaN(n)) return '0000' + n.toString(16).padStart(4, '0') + '-0000-1000-8000-00805f9b34fb';
      return _uuidAliases[uuid.toLowerCase()] || uuid;
    }
    return uuid;
  }

  // ── navigator.bluetooth ─────────────────────────────────────────────────────
  Object.defineProperty(navigator, 'bluetooth', {
    value: {
      getAvailability: function () { return Promise.resolve(true); },
      requestDevice: function (options) {
        return _call('requestDevice', options || {})
          .then(function (r) { return makeDevice(r.deviceId, r.name); });
      }
    },
    writable: false, configurable: false
  });

})();
