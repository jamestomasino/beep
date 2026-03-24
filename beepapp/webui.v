module beepapp

import json
import net
import os

const ui_embed = $embed_file('../assets/ui/index.html')

fn http_response(status string, content_type string, body string) string {
	return 'HTTP/1.1 ${status}\r\nContent-Type: ${content_type}\r\nCache-Control: no-store\r\nContent-Length: ${body.len}\r\nConnection: close\r\n\r\n${body}'
}

fn write_json(mut conn net.TcpConn, resp ControlResponse) {
	conn.write_string(http_response('200 OK', 'application/json', json.encode(resp))) or {}
}

fn write_text(mut conn net.TcpConn, code string, body string) {
	conn.write_string(http_response(code, 'text/plain; charset=utf-8', body)) or {}
}

fn load_ui_html() string {
	html := ui_embed.to_string()
	if html.len > 0 {
		return html
	}
	asset_path := os.join_path(@VMODROOT, 'assets', 'ui', 'index.html')
	return os.read_file(asset_path) or {
		'<!doctype html><html><body><h1>beep UI missing</h1><p>Expected asset: ${asset_path}</p></body></html>'
	}
}

pub fn default_ui_addr() string {
	return os.getenv_opt('BEEP_UI_ADDR') or { '127.0.0.1:48778' }
}

pub fn run_web_ui_server(addr string, ipc_addr string) ! {
	mut ln := net.listen_tcp(.ip, addr)!
	defer {
		ln.close() or {}
	}
	for {
		mut conn := ln.accept() or { continue }
		spawn handle_web_ui_conn(mut conn, ipc_addr)
	}
}

fn handle_web_ui_conn(mut conn net.TcpConn, ipc_addr string) {
	defer {
		conn.close() or {}
	}
	request_line := conn.read_line()
	if request_line.len == 0 {
		return
	}
	for {
		h := conn.read_line()
		if h.len == 0 || h == '\r\n' {
			break
		}
	}
	parts := request_line.split(' ')
	if parts.len < 2 || parts[0] != 'GET' {
		write_text(mut conn, '405 Method Not Allowed', 'method not allowed\n')
		return
	}
	raw_target := parts[1]
	target := raw_target.all_before('?')

	if target == '/' {
		conn.write_string(http_response('200 OK', 'text/html; charset=utf-8', load_ui_html())) or {}
		return
	}

	if target == '/api/state' {
		resp := send_control(ipc_addr, ControlRequest{cmd: 'get_state'}) or {
			write_text(mut conn, '503 Service Unavailable', 'daemon unavailable\n')
			return
		}
		write_json(mut conn, resp)
		return
	}

	if target == '/api/save' {
		resp := send_control(ipc_addr, ControlRequest{cmd: 'save_config'}) or {
			write_text(mut conn, '503 Service Unavailable', 'daemon unavailable\n')
			return
		}
		write_json(mut conn, resp)
		return
	}

	if target == '/api/quit' {
		resp := send_control(ipc_addr, ControlRequest{cmd: 'quit'}) or {
			write_text(mut conn, '503 Service Unavailable', 'daemon unavailable\n')
			return
		}
		write_json(mut conn, resp)
		return
	}

	if target.starts_with('/api/profile/') {
		value := target['/api/profile/'.len..]
		resp := send_control(ipc_addr, ControlRequest{
			cmd:   'set'
			key:   'profile'
			value: value
		}) or {
			write_text(mut conn, '503 Service Unavailable', 'daemon unavailable\n')
			return
		}
		write_json(mut conn, resp)
		return
	}

	if target.starts_with('/api/toggle/') {
		key := target['/api/toggle/'.len..]
		resp := send_control(ipc_addr, ControlRequest{
			cmd: 'toggle'
			key: key
		}) or {
			write_text(mut conn, '503 Service Unavailable', 'daemon unavailable\n')
			return
		}
		write_json(mut conn, resp)
		return
	}

	if target.starts_with('/api/set/') {
		rest := target['/api/set/'.len..]
		sep := rest.index('/') or {
			write_text(mut conn, '400 Bad Request', 'missing key/value\n')
			return
		}
		if sep <= 0 || sep >= rest.len - 1 {
			write_text(mut conn, '400 Bad Request', 'invalid key/value\n')
			return
		}
		key := rest[..sep]
		raw_value := rest[sep + 1..]
		resp := send_control(ipc_addr, ControlRequest{
			cmd:   'set'
			key:   key
			value: raw_value
		}) or {
			write_text(mut conn, '503 Service Unavailable', 'daemon unavailable\n')
			return
		}
		write_json(mut conn, resp)
		return
	}

	write_text(mut conn, '404 Not Found', 'not found\n')
}
