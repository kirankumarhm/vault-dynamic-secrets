package com.hashicorp.vaultdynamicsecrets;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.scheduling.annotation.EnableScheduling;

@SpringBootApplication
@EnableScheduling
public class VaultDynamicSecretsApplication {

	public static void main(String[] args) {
		SpringApplication.run(VaultDynamicSecretsApplication.class, args);
	}

}
