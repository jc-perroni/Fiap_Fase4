#!/usr/bin/env python3
"""
Docker Stats Exporter - Coleta métricas via docker stats e expõe no formato Prometheus
Compatível com Docker Desktop no macOS
"""

import subprocess
import json
import time
import re
from http.server import HTTPServer, BaseHTTPRequestHandler
from threading import Thread

class DockerStatsCollector:
    def __init__(self):
        self.metrics = {}
        self.project_name = "fase04"
        
    def collect(self):
        try:
            # Executa docker stats --no-stream --format json
            result = subprocess.run(
                ['docker', 'stats', '--no-stream', '--format', '{{json .}}'],
                capture_output=True,
                text=True,
                timeout=10
            )
            
            if result.returncode != 0:
                print(f"Error running docker stats: {result.stderr}")
                return {}
            
            metrics = {}
            containers_total = 0
            containers_running = 0
            services = set()
            
            for line in result.stdout.strip().split('\n'):
                if not line:
                    continue
                    
                try:
                    stat = json.loads(line)
                    container_name = stat.get('Name', '')
                    
                    # Filtrar apenas containers do projeto
                    if self.project_name not in container_name:
                        continue
                    
                    containers_total += 1
                    
                    # Extrair nome do serviço
                    service_match = re.search(rf'{self.project_name}[-_]([a-zA-Z0-9-]+)[-_]', container_name)
                    if service_match:
                        service_name = service_match.group(1)
                        services.add(service_name)
                    
                    # CPU usage
                    cpu_str = stat.get('CPUPerc', '0%').replace('%', '')
                    try:
                        cpu_value = float(cpu_str)
                    except:
                        cpu_value = 0
                    
                    # Memory usage
                    mem_usage = stat.get('MemUsage', '0B / 0B').split('/')[0].strip()
                    mem_bytes = self._parse_size(mem_usage)
                    
                    # Network I/O
                    net_io = stat.get('NetIO', '0B / 0B')
                    net_rx, net_tx = net_io.split('/')
                    net_rx_bytes = self._parse_size(net_rx.strip())
                    net_tx_bytes = self._parse_size(net_tx.strip())
                    
                    # Block I/O
                    block_io = stat.get('BlockIO', '0B / 0B')
                    block_read, block_write = block_io.split('/')
                    block_read_bytes = self._parse_size(block_read.strip())
                    block_write_bytes = self._parse_size(block_write.strip())
                    
                    # Labels
                    labels = f'container_name="{container_name}",project="{self.project_name}"'
                    if service_match:
                        labels += f',service="{service_name}"'
                    
                    # Adicionar métricas
                    metrics[f'container_cpu_usage_percent{{{labels}}}'] = cpu_value
                    metrics[f'container_memory_usage_bytes{{{labels}}}'] = mem_bytes
                    metrics[f'container_network_receive_bytes{{{labels}}}'] = net_rx_bytes
                    metrics[f'container_network_transmit_bytes{{{labels}}}'] = net_tx_bytes
                    metrics[f'container_fs_read_bytes{{{labels}}}'] = block_read_bytes
                    metrics[f'container_fs_write_bytes{{{labels}}}'] = block_write_bytes
                    
                    containers_running += 1
                    
                except json.JSONDecodeError:
                    continue
                except Exception as e:
                    print(f"Error parsing stats: {e}")
                    continue
            
            # Métricas agregadas
            metrics['containers_total'] = containers_total
            metrics['containers_running'] = containers_running
            metrics['services_active'] = len(services)
            
            return metrics
            
        except subprocess.TimeoutExpired:
            print("Docker stats timeout")
            return {}
        except Exception as e:
            print(f"Error collecting metrics: {e}")
            return {}
    
    def _parse_size(self, size_str):
        """Converte string de tamanho (ex: 100MiB) para bytes"""
        size_str = size_str.strip()
        if not size_str or size_str == '0' or size_str == '0B':
            return 0
        
        # Remove espaços e converte para uppercase
        size_str = size_str.replace(' ', '').upper()
        
        # Mapeamento de unidades (ordenado do maior para o menor para evitar matches parciais)
        units = [
            ('TIB', 1024**4),
            ('TIB', 1024**4),
            ('GIB', 1024**3),
            ('MIB', 1024**2),
            ('KIB', 1024),
            ('TB', 1000**4),
            ('GB', 1000**3),
            ('MB', 1000**2),
            ('KB', 1000),
            ('B', 1),
        ]
        
        # Encontrar a unidade (verifica unidades maiores primeiro)
        for unit, multiplier in units:
            if size_str.endswith(unit):
                try:
                    value_str = size_str[:-len(unit)]
                    if value_str:
                        value = float(value_str)
                        return int(value * multiplier)
                except (ValueError, IndexError):
                    continue
        
        # Tentar converter direto (já em bytes)
        try:
            return int(float(size_str))
        except:
            return 0


class MetricsHandler(BaseHTTPRequestHandler):
    collector = DockerStatsCollector()
    
    def do_GET(self):
        if self.path == '/metrics':
            metrics = self.collector.collect()
            
            # Formatar resposta Prometheus
            response = self._format_metrics(metrics)
            
            self.send_response(200)
            self.send_header('Content-Type', 'text/plain; charset=utf-8')
            self.end_headers()
            self.wfile.write(response.encode('utf-8'))
        elif self.path == '/health':
            self.send_response(200)
            self.send_header('Content-Type', 'text/plain')
            self.end_headers()
            self.wfile.write(b'OK')
        else:
            self.send_response(404)
            self.end_headers()
    
    def _format_metrics(self, metrics):
        lines = []
        lines.append('# HELP containers_total Total number of containers')
        lines.append('# TYPE containers_total gauge')
        lines.append(f"containers_total {metrics.get('containers_total', 0)}")
        lines.append('')
        
        lines.append('# HELP containers_running Number of running containers')
        lines.append('# TYPE containers_running gauge')
        lines.append(f"containers_running {metrics.get('containers_running', 0)}")
        lines.append('')
        
        lines.append('# HELP services_active Number of active services')
        lines.append('# TYPE services_active gauge')
        lines.append(f"services_active {metrics.get('services_active', 0)}")
        lines.append('')
        
        lines.append('# HELP container_cpu_usage_percent CPU usage percentage')
        lines.append('# TYPE container_cpu_usage_percent gauge')
        lines.append('# HELP container_memory_usage_bytes Memory usage in bytes')
        lines.append('# TYPE container_memory_usage_bytes gauge')
        lines.append('# HELP container_network_receive_bytes Network received bytes')
        lines.append('# TYPE container_network_receive_bytes counter')
        lines.append('# HELP container_network_transmit_bytes Network transmitted bytes')
        lines.append('# TYPE container_network_transmit_bytes counter')
        lines.append('# HELP container_fs_read_bytes Filesystem read bytes')
        lines.append('# TYPE container_fs_read_bytes counter')
        lines.append('# HELP container_fs_write_bytes Filesystem write bytes')
        lines.append('# TYPE container_fs_write_bytes counter')
        
        for metric_name, value in metrics.items():
            if metric_name not in ['containers_total', 'containers_running', 'services_active']:
                lines.append(f"{metric_name} {value}")
        
        return '\n'.join(lines)
    
    def log_message(self, format, *args):
        # Suprimir logs HTTP
        pass


def main():
    port = 9417
    server = HTTPServer(('', port), MetricsHandler)
    print(f"Docker Stats Exporter listening on port {port}")
    print(f"Metrics available at http://localhost:{port}/metrics")
    server.serve_forever()


if __name__ == '__main__':
    main()
