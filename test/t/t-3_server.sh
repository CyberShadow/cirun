#!/bin/bash
source ./lib.bash

mv cirun.conf cirun.conf.initial

counter=0

for transport in inet unix stdin accept
do
	for protocol in http cgi scgi fastcgi
	do
		for nph in implicit-no implicit-yes no yes
		do
			for frontend in none apache nginx
			do
				counter=$((counter+1))
				(
					printf -- '-------\n[%d] Testing transport=%s protocol=%s nph=%s frontend=%s\n' \
						   $counter $transport $protocol $nph $frontend
					id=$transport-$protocol-$nph-$frontend

					if [[ $frontend == none && $protocol != http ]]
					then
						printf ' > Cannot test protocol %s directly\n' "$protocol"
						exit
					fi

					if [[ $frontend == none && $transport == accept ]]
					then
						printf ' > Need a frontend for transport=accept\n'
						exit
					fi

					if [[ $protocol == cgi && $transport != stdin ]]
					then
						printf ' > CGI requires transport=stdin\n'
						exit
					fi

					if [[ $frontend == nginx && ( $transport == stdin || $transport == accept ) ]]
					then
						printf ' > Nginx cannot stdin/accept\n'
						exit
					fi

					if [[ $frontend == apache && $transport == stdin && $protocol != cgi ]]
					then
						printf ' > Apache can use stdin only for CGI\n'
						exit
					fi

					if [[ $frontend == apache && $transport == accept && $protocol != fastcgi ]]
					then
						printf ' > Apache can use accept only for FastCGI\n'
						exit
					fi

					if [[ $nph != implicit-no && $protocol != *cgi ]]
					then
						printf ' > NPH only makes sense for *CGI\n'
						exit
					fi

					if [[ $nph == implicit-yes && ( $transport == inet || $transport == unix ) ]]
					then
						printf ' > NPH cannot be implicit when talking over a socket\n'
						exit
					fi

					if [[ $nph != implicit-* && $frontend == apache ]]
					then
						printf ' > Cannot explicitly configure NPH in Apache\n'
						exit
					fi

					if [[ $nph == implicit-yes && $frontend == apache ]]
					then
						printf ' > TODO find how to enable NPH with mod_fcgid\n'
						exit
					fi

					if [[ $nph != implicit-* && $frontend == nginx ]]
					then
						printf ' > Cannot explicitly configure NPH in Nginx\n'
						exit
					fi

					mkdir "$id"
					cd "$id"
					ln -s "$cirun" cirun
					cirun=$PWD/cirun

					{
						cat ../cirun.conf.initial
						cat <<-EOF
						[server.$protocol]
						transport = $transport
						protocol = $protocol
						EOF
						case $transport in
							inet)
								echo "listen.addr = $test_ip"
								echo "listen.port = $test_port2"
								;;
							unix)
								echo "listen.socketPath = cirun.sock"
								;;
							stdin|accept)
								;;
						esac
						case $nph in
							implicit-no)
								;;
							implicit-yes)
								ln -s "$cirun" nph-cirun
								cirun=$PWD/nph-cirun
								;;
							no)
								echo "nph = false"
								;;
							yes)
								echo "nph = true"
								;;
						esac
					} > cirun.conf

					function cleanup() {
						if [[ -v pid_cirun ]]
						then
							kill "$pid_cirun"
						fi
						if [[ -v pid_httpd ]]
						then
							kill "$pid_httpd"
						fi
						wait -f
					}
					trap cleanup EXIT

					ncat_command=(ncat)
					ncat_target=("$test_ip" "$test_port")

					case $frontend in
						none)
							case $transport in
								inet)
									ncat_target=("$test_ip" "$test_port2")
									;;
								unix)
									ncat_target=(-U cirun.sock)
									;;
							esac
							;;
						apache)
							{
								cat <<-EOF
								ServerName 127.0.0.1
								ServerAdmin cirun@localhost
								PidFile "$PWD/apache.pid"
								Listen ${test_ip}:${test_port}
								ErrorLog /dev/stderr

								LoadModule alias_module modules/mod_alias.so
								LoadModule authz_core_module modules/mod_authz_core.so
								LoadModule unixd_module modules/mod_unixd.so
								LoadModule mpm_prefork_module modules/mod_mpm_prefork.so
								EOF

								case $transport in
									inet|unix)
										case $protocol in
											http)
												h_mod=http
												;;
											scgi)
												h_mod=scgi
												;;
											fastcgi)
												h_mod=fcgi
												;;
											*)
												echo huh 1>&2 ; exit 1
										esac
										case $transport in
											inet)
												h_url=${h_mod}://$test_ip:$test_port2/
												;;
											unix)
												h_url="unix:$PWD/cirun.sock|${h_mod}://localhost/"
												;;
										esac
										cat <<-EOF
                                        LoadModule proxy_module modules/mod_proxy.so
										LoadModule proxy_${h_mod}_module modules/mod_proxy_${h_mod}.so
										ProxyPass "/" "${h_url}"
										EOF
										;;
									stdin)
										# protocol can only be CGI
										cat <<-EOF
                                        LoadModule cgi_module modules/mod_cgi.so
                                        ScriptAlias "/" "$(realpath "$(dirname "$cirun")")/"
										EOF
										case $nph in
											implicit-no)
												url_prefix=/cirun
												;;
											implicit-yes)
												url_prefix=/nph-cirun
												;;
										esac
										;;
									accept)
										# protocol can only be FastCGI
										cat <<-EOF
                                        LoadModule fcgid_module modules/mod_fcgid.so

										Suexec Off
										FcgidIPCDir "$PWD"
										FcgidProcessTableFile "$PWD/fcgid_shm"

										<Directory "$(realpath "$(dirname "$cirun")")/">
											SetHandler fcgid-script
											Options +ExecCGI
										</Directory>

										ScriptAlias "/" "$(realpath "$(dirname "$cirun")")/"
										EOF
										case $nph in
											implicit-no)
												url_prefix=/cirun
												;;
											implicit-yes)
												url_prefix=/nph-cirun
												;;
										esac
										;;
									*)
										echo huh 1>&2 ; exit 1
								esac
							} > apache.conf

							httpd -f "$PWD"/apache.conf -X &
							pid_httpd=$!
							sleep 0.2
							;;
						nginx)
							{
								cat <<-EOF
								daemon off;
								pid        $test_dir/nginx.pid;

								events {}

								http {
								  client_body_temp_path $test_dir;
								  fastcgi_temp_path $test_dir;
								  uwsgi_temp_path $test_dir;
								  scgi_temp_path $test_dir;
								  access_log   $test_dir/access.log;

								  server {
									listen       $test_ip:$test_port;

									location / {
								EOF
								
								case $transport in
									inet|unix)
										case $transport in
											inet)
												h_addr=$test_ip:$test_port2
												;;
											unix)
												h_addr=unix:$PWD/cirun.sock
												;;
										esac
										case $protocol in
											http)
												cat <<-EOF
												proxy_pass   http://$h_addr;
												EOF
												;;
											scgi)
												cat <<-EOF
												include /etc/nginx/scgi_params;
												scgi_pass   $h_addr;
												EOF
												;;
											fastcgi)
												cat <<-EOF
												include /etc/nginx/fastcgi_params;
												fastcgi_pass   $h_addr;
												EOF
												;;
											*)
												echo huh 1>&2 ; exit 1
										esac
										;;
									*)
										echo huh 1>&2 ; exit 1
								esac
									  
								cat <<-EOF
									}
								  }
								}
								EOF
							} > nginx.conf

							nginx -c "$PWD"/nginx.conf &
							pid_httpd=$!
							;;
					esac

					if [[ -v url_prefix ]]
					then
						echo "prefix = $url_prefix/" >> cirun.conf
					else
						url_prefix=
					fi

					case $transport in
						inet|unix)
							"$cirun" server &
							pid_cirun=$!
							sleep 0.1
							;;
						stdin)
							if [[ "$frontend" == none ]]
							then
								ncat_command=("$cirun" server "$protocol")
								ncat_target=()
							fi
							;;
					esac

					rm -f .done
					{
						printf 'GET %s/ping HTTP/1.0\r\n\r\n' "$url_prefix"
						while [[ ! -f .done ]] ; do sleep 0.1 ; done
					} |
						"${ncat_command[@]}" "${ncat_target[@]}" |
						{
							# Skip headers
							while read -r line
							do
								re=$'^\r?$'
								if [[ "$line" =~ $re ]]
								then
									break
								fi
							done

							touch .done

							# Pass body
							cat
						} |
						diff -u /dev/stdin <(echo pong)
				)
			done
		done
	done
done
