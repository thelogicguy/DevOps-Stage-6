FROM maven:3.9-eclipse-temurin-17 AS builder

WORKDIR /app

COPY pom.xml .
RUN mvn dependency:go-offline -B

COPY src ./src
RUN mvn clean package -DskipTests

FROM eclipse-temurin:17-jre

RUN apt-get update && \
    apt-get install -y wget && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY --from=builder /app/target/*.jar app.jar

RUN groupadd -g 1001 spring && \
    useradd -r -u 1001 -g spring spring && \
    chown -R spring:spring /app

USER spring

EXPOSE 8081

HEALTHCHECK --interval=30s --timeout=3s --start-period=30s --retries=3 \
  CMD wget --no-verbose --tries=1 --spider http://127.0.0.1:8081/actuator/health 2>&1 | grep -q '500\|200' || exit 1

ENTRYPOINT ["java", "--add-opens", "java.base/java.lang=ALL-UNNAMED", "--add-opens", "java.base/java.lang.invoke=ALL-UNNAMED", "--add-opens", "java.base/java.lang.reflect=ALL-UNNAMED", "--add-opens", "java.base/java.io=ALL-UNNAMED", "--add-opens", "java.base/java.security=ALL-UNNAMED", "--add-opens", "java.base/java.util=ALL-UNNAMED", "--add-opens", "java.base/java.net=ALL-UNNAMED", "-jar", "app.jar"]